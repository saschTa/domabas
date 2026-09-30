import { mkdir, open } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { parseArgs } from "node:util";
import { command, ProcessScope, ROOT, runCLI } from "../shared/runtime.ts";

export interface ContainerMemory {
  currentBytes: number;
  peakBytes: number;
  limitBytes: number | null;
  workingSetBytes: number;
  anonymousBytes: number;
  fileBytes: number;
  sharedBytes: number;
  oom: number;
  oomKills: number;
}

export function parseContainerMemory(output: string): ContainerMemory {
  const [current, peak, limit, ...lines] = output.trim().split(/\r?\n/);
  const integer = (value: string | undefined): number => {
    if (!value || !/^\d+$/.test(value) || !Number.isSafeInteger(Number(value))) throw new Error("Invalid cgroup memory counter.");
    return Number(value);
  };
  const counters = new Map(lines.map(line => {
    const [key, value] = line.trim().split(/\s+/);
    return [key, integer(value)] as const;
  }));
  const counter = (key: string): number => {
    const value = counters.get(key);
    if (value === undefined) throw new Error(`Missing cgroup memory counter: ${key}.`);
    return value;
  };
  const currentBytes = integer(current);
  const inactiveFileBytes = counter("inactive_file");
  return {
    currentBytes, peakBytes: integer(peak), limitBytes: limit === "max" ? null : integer(limit),
    workingSetBytes: inactiveFileBytes < currentBytes ? currentBytes - inactiveFileBytes : currentBytes,
    anonymousBytes: counter("anon"), fileBytes: counter("file"), sharedBytes: counter("shmem"),
    oom: counter("oom"), oomKills: counter("oom_kill"),
  };
}

interface ContainerState {
  id: string;
  name: string;
  service: string;
  image: string;
  imageID: string;
  running: boolean;
  startedAt: string;
  finishedAt: string;
  oomKilled: boolean;
  exitCode: number;
  restarts: number;
  limitBytes: number;
}

export interface MemorySample {
  timestamp: string;
  project: string;
  containers: (ContainerState & { memory: ContainerMemory | null; error?: string })[];
  nonOllamaCurrentBytes: number;
  nonOllamaWorkingSetBytes: number;
  complete: boolean;
}

export async function sampleMemory(scope: ProcessScope, project: string): Promise<MemorySample> {
  if (!/^[a-z0-9][a-z0-9_-]*$/.test(project)) throw new Error("Invalid Compose project name.");
  const docker = command("docker");
  const discovered = await scope.capture([docker, "ps", "-aq", "--filter", `label=com.docker.compose.project=${project}`]);
  if (discovered.code) throw new Error(`Cannot list project containers: ${discovered.stderr.trim()}`);
  const ids = discovered.stdout.trim().split(/\s+/).filter(Boolean);
  if (!ids.length) throw new Error(`No containers found for Compose project '${project}'.`);
  const format = '{"id":{{json .Id}},"name":{{json .Name}},"service":{{json (index .Config.Labels "com.docker.compose.service")}},"image":{{json .Config.Image}},"imageID":{{json .Image}},"running":{{.State.Running}},"startedAt":{{json .State.StartedAt}},"finishedAt":{{json .State.FinishedAt}},"oomKilled":{{.State.OOMKilled}},"exitCode":{{.State.ExitCode}},"restarts":{{.RestartCount}},"limitBytes":{{.HostConfig.Memory}}}';
  const inspected = await scope.capture([docker, "inspect", "--format", format, ...ids]);
  if (inspected.code) throw new Error(`Cannot inspect project containers: ${inspected.stderr.trim()}`);
  const states = inspected.stdout.trim().split(/\r?\n/).map(line => JSON.parse(line) as ContainerState);
  const results = await Promise.allSettled(states.map(async state => {
    if (!state.running) return { ...state, memory: null };
    const result = await scope.capture([docker, "exec", state.id, "cat", ...["current", "peak", "max", "stat", "events"].map(name => `/sys/fs/cgroup/memory.${name}`)]);
    if (result.code) return { ...state, memory: null, error: "Cannot read cgroup v2 memory counters (container may have stopped or host uses cgroup v1)." };
    return { ...state, memory: parseContainerMemory(result.stdout) };
  }));
  const containers = results.map((result, index) => {
    if (result.status === "fulfilled") return result.value;
    return { ...states[index]!, memory: null, error: result.reason instanceof Error ? result.reason.message : String(result.reason) };
  });
  scope.signal.throwIfAborted();
  const nonOllama = containers.filter(container => container.service !== "ollama");
  return {
    timestamp: new Date().toISOString(), project, containers,
    nonOllamaCurrentBytes: nonOllama.reduce((total, container) => total + (container.memory?.currentBytes ?? 0), 0),
    nonOllamaWorkingSetBytes: nonOllama.reduce((total, container) => total + (container.memory?.workingSetBytes ?? 0), 0),
    complete: containers.every(container => !container.running || container.memory !== null),
  };
}

export function positiveSeconds(value: string, maximum: number): number {
  if (!/^\d+$/.test(value) || Number(value) < 1 || Number(value) > maximum) throw new Error(`Duration must be an integer between 1 and ${maximum} seconds.`);
  return Number(value);
}

if (import.meta.main) await runCLI(async scope => {
  const { values } = parseArgs({ args: Bun.argv.slice(2), options: {
    project: { type: "string", default: "domabas" }, duration: { type: "string", default: "900" },
    interval: { type: "string", default: "10" }, output: { type: "string" }, help: { type: "boolean", short: "h" },
  } });
  if (values.help) { console.log("Usage: task diagnose:memory -- --project=domabas --duration=900 --interval=10 [--output=PATH]\nRead-only Docker cgroup v2 sampling; excludes Ollama from totals, records every container. Requires a running stack; never starts or stops it."); return; }
  const duration = positiveSeconds(values.duration!, 86400) * 1000;
  const interval = positiveSeconds(values.interval!, 3600) * 1000;
  const destination = resolve(values.output ?? `${ROOT}/.logs/memory-${Date.now()}.jsonl`);
  await mkdir(dirname(destination), { recursive: true });
  const file = await open(destination, "wx", 0o600);
  console.log(`Recording ${values.project} to ${destination}`);
  const deadline = performance.now() + duration;
  try {
    do {
      scope.signal.throwIfAborted();
      const sample = await sampleMemory(scope, values.project!);
      await file.write(`${JSON.stringify(sample)}\n`);
      console.log(`${sample.timestamp} non-Ollama: ${(sample.nonOllamaCurrentBytes / 2 ** 20).toFixed(1)} MiB cgroup, ${(sample.nonOllamaWorkingSetBytes / 2 ** 20).toFixed(1)} MiB working set${sample.complete ? "" : " (INCOMPLETE; see errors)"}`);
      for (const container of sample.containers) {
        if (container.oomKilled || container.memory?.oomKills || container.restarts || (!container.running && container.exitCode !== 0) || container.error) console.log(`${container.service}: running=${container.running} exit=${container.exitCode} restarts=${container.restarts} OOMKilled=${container.oomKilled} oomKills=${container.memory?.oomKills ?? "unknown"} ${container.error ?? ""}`);
      }
      const next = Math.min(deadline, performance.now() + interval);
      while (performance.now() < next) {
        scope.signal.throwIfAborted();
        await Bun.sleep(Math.min(250, Math.max(0, next - performance.now())));
      }
    } while (performance.now() < deadline);
  } finally { await file.close(); }
});
