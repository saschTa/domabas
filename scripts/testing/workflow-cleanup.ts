import { captureCompose } from "../development/compose.ts";
import { type Environment, ProcessScope, required } from "../shared/runtime.ts";

export interface OwnedExecution { workflowId: string; runId: string; taskQueue: string; workflowType: string }
interface ExecutionInfo { execution?: { workflowId?: string; runId?: string }; type?: { name?: string }; taskQueue?: string; status?: string }

export function ownedExecutions(value: unknown, queue: string): OwnedExecution[] {
  if (!Array.isArray(value) || value.length > 10000) throw new Error("Invalid owned workflow cleanup manifest.");
  return value.map(item => {
    if (!item || typeof item !== "object") throw new Error("Invalid owned workflow identity.");
    const entry = item as Record<string, unknown>;
    if (![entry.workflowId, entry.runId, entry.taskQueue, entry.workflowType].every(v => typeof v === "string")) throw new Error("Invalid owned workflow identity.");
    const result = entry as unknown as OwnedExecution;
    const uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
    const email = result.workflowType === "domabas.EmailPoll.v1" && result.taskQueue === `${queue}-email` && new RegExp(`^domabas-email-${uuid}$`).test(result.workflowId);
    const paperless = result.workflowType === "domabas.PaperlessImport.v1" && result.taskQueue === `${queue}-paperless` && new RegExp(`^domabas-paperless-${uuid}$`).test(result.workflowId);
    const document = [1, 2].some(version => result.workflowType === `domabas.DocumentIngestion.v${version}` && result.taskQueue === queue && new RegExp(`^document-ingestion-v${version}/${uuid}/${uuid}/[1-9][0-9]*$`).test(result.workflowId));
    const ai = result.workflowType === "domabas.DocumentAI.v1" && result.taskQueue === `${queue}-ai` && new RegExp(`^document-ai-v1/${uuid}/${uuid}/[1-9][0-9]*/[1-9][0-9]*$`).test(result.workflowId);
    const chat = result.workflowType === "domabas.ChatTurn.v1" && result.taskQueue === `${queue}-chat` && new RegExp(`^domabas-chat-${uuid}$`).test(result.workflowId);
    const thumbnail = result.workflowType === "domabas.DocumentThumbnail.v1" && result.taskQueue === `${queue}-thumbnail` && new RegExp(`^document-thumbnail-v1/${uuid}$`).test(result.workflowId);
    if ((!email && !document && !paperless && !ai && !chat && !thumbnail) || (result.runId !== "" && !new RegExp(`^${uuid}$`).test(result.runId))) throw new Error("Workflow cleanup manifest does not belong to the disposable queue.");
    return result;
  });
}

export function exactTermination(entry: OwnedExecution, value: unknown): string | undefined {
  if (!value || typeof value !== "object") throw new Error("Cannot verify owned workflow execution.");
  const info = (value as { workflowExecutionInfo?: ExecutionInfo }).workflowExecutionInfo;
  const run = info?.execution?.runId;
  if (!info || !run || info.execution?.workflowId !== entry.workflowId || (entry.runId !== "" && run !== entry.runId) || info.taskQueue !== entry.taskQueue || info.type?.name !== entry.workflowType) throw new Error("Workflow cleanup ownership mismatch; execution left untouched.");
  if (info.status === "WORKFLOW_EXECUTION_STATUS_RUNNING" || info.status === "Running") return run;
  if (!["WORKFLOW_EXECUTION_STATUS_COMPLETED", "WORKFLOW_EXECUTION_STATUS_FAILED", "WORKFLOW_EXECUTION_STATUS_CANCELED", "WORKFLOW_EXECUTION_STATUS_TERMINATED", "WORKFLOW_EXECUTION_STATUS_CONTINUED_AS_NEW", "WORKFLOW_EXECUTION_STATUS_TIMED_OUT", "Completed", "Failed", "Canceled", "Terminated", "ContinuedAsNew", "TimedOut"].includes(info.status ?? "")) throw new Error("Unrecognized workflow cleanup status.");
  return undefined;
}

export function containerTemporalAddress(address: string, publishedPort?: number): string {
  const match = /^(127\.0\.0\.1|localhost|\[::1\]):([1-9][0-9]*)$/.exec(address);
  if (match && Number(match[2]) === publishedPort) return "temporal:7233";
  return match ? `host.docker.internal:${match[2]}` : address;
}

export async function cleanupWorkflows(scope: ProcessScope, env: Environment, entries: OwnedExecution[]): Promise<void> {
  if (!entries.length) return;
  const executable = Bun.which("temporal");
  const address = required(env, "TEMPORAL_ADDRESS"), namespace = required(env, "TEMPORAL_NAMESPACE");
  let containerAddress = containerTemporalAddress(address);
  if (!executable) {
    const port = await captureCompose(scope, ["port", "temporal", "7233"], env, 20000);
    const published = port.code ? undefined : Number(/:(\d+)\s*$/.exec(port.stdout)?.[1]);
    containerAddress = containerTemporalAddress(address, published);
  }
  const call = async (args: string[]) => {
    const shared = ["--disable-config-file", "--disable-config-env", "--address", executable ? address : containerAddress, "--namespace", namespace, "--command-timeout", "15s", "--output", "json", ...args];
    return executable
      ? scope.capture([executable, ...shared], { env }, 20000)
      : captureCompose(scope, ["run", "--rm", "--no-deps", "--entrypoint", "temporal", "temporal-init", ...shared], env, 20000);
  };
  for (const entry of entries) {
    const identity = ["--workflow-id", entry.workflowId, ...(entry.runId ? ["--run-id", entry.runId] : [])];
    const result = await call(["workflow", "describe", "--raw", ...identity]);
    if (result.code) {
      if (/workflow execution not found|workflow not found/i.test(result.stderr)) continue;
      throw new Error("Cannot inspect disposable workflows. Provide a reachable Temporal CLI or the Compose initializer image and network; schema cleanup has stopped.");
    }
    const run = exactTermination(entry, JSON.parse(result.stdout));
    if (!run) continue;
    const terminated = await call(["workflow", "terminate", "--workflow-id", entry.workflowId, "--run-id", run, "--reason", "owned browser E2E cleanup"]);
    if (terminated.code && !/workflow execution.*(not found|already completed)|workflow.*not running/i.test(terminated.stderr)) throw new Error("Cannot terminate the exact owned browser test execution.");
  }
}
