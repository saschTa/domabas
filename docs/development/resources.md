# Runtime resources and memory diagnosis

For a small home installation with one admitted ingestion job, start with
**4 CPU cores and 5 GiB of available RAM for Domabas**, plus memory for Ollama
models when using AI. Add capacity for the host OS, Docker VM overhead,
TrueNAS/ZFS and other apps. Search embeddings also use Ollama, independently of
optional chat and invoice/property AI, so include that model in your allowance.
For Docker Desktop or Rancher Desktop, the VM allocation must cover the
containers, independently of installed host RAM; native Ollama uses host memory.

This is a starting recommendation, not a benchmarked minimum or enough headroom
for every service to reach its configured ceiling at once. Large documents,
bulk imports, larger models and higher concurrency can require more memory.
Measure the workload and adjust capacity or concurrency when needed.

## Default service budgets

| Service | Container RAM ceiling | Go runtime soft target | Compose override |
| --- | --- | --- | --- |
| PostgreSQL | 2 GiB | — | `POSTGRES_MEMORY_LIMIT` |
| Temporal server | 2 GiB | 1536 MiB | `TEMPORAL_MEMORY_LIMIT`, `TEMPORAL_GOMEMLIMIT` |
| Backend, including all application workers | 2 GiB | 1536 MiB | `BACKEND_MEMORY_LIMIT`, `BACKEND_GOMEMLIMIT` |
| Document processor and extraction children | 4 GiB | — | `DOCUMENT_PROCESSOR_MEMORY_LIMIT` |
| Temporal UI | 256 MiB | 192 MiB | `TEMPORAL_UI_MEMORY_LIMIT`, `TEMPORAL_UI_GOMEMLIMIT` |
| Web server | 512 MiB | — | `WEB_MEMORY_LIMIT` |
| Ollama | 8 GiB | — | `OLLAMA_MEMORY_LIMIT` |

The long-running ceilings total **10.75 GiB excluding Ollama**, or
**18.75 GiB including it**. These are upper limits, not the RAM needed to start a
small installation. Ceilings do not preallocate memory and do not reserve it on
an overcommitted host. A 5 GiB base allocation cannot absorb every simultaneous
peak; raising limits or concurrency requires revisiting total capacity.
Initialization/build processes, native Go/Flutter development, browsers and
container image builds are additional consumers.

Compose supplies service-specific `GOMEMLIMIT` values to the three Go servers.
The targets leave 25% below their container ceilings. Go's limit is soft and
covers runtime-managed memory, not all RSS, kernel charges or child processes;
it can be exceeded when live allocations cannot be collected. It cannot cure a
leak. Adjust both values together when changing a service's ceiling. The
processor deliberately retains only its container limit: OCR and PDF child
processes share that budget and have native/WASM allocations.

PostgreSQL keeps its existing connection and query-memory settings. Its RAM cap
does not make query memory a single shared pool. Reassess database sizing for
large indexes, many simultaneous queries or bulk maintenance.

The processor's separate 2 GiB `/tmp` tmpfs counts within its 4 GiB ceiling when
used; it is not another 2 GiB reservation. The image defaults `TMPDIR` to the
private, disk-backed `/app/tmp` for queued originals, compiled PDF code and OCR
scratch. Keep writable scratch disk capacity available: the bounded request
queue can spool many 100 MiB originals, and active OCR also needs temporary
space. Do not move all scratch to tmpfs without measuring the resulting RAM
demand. See [processing bounds](../arch/backend/document-ingestion.md).

Start with the default Ollama job limit of `1` in Admin settings → Workload
limits. Lower the shared worker limit if CPU processing or total memory is under
pressure, and increase limits only after measuring the host. The former ingestion
and document AI concurrency environment settings, including `auto`, no longer
control admission. See [shared resource scheduling](../arch/backend/resource-scheduler.md).
A GPU does not eliminate CPU OCR, database or Temporal memory. An integrated GPU
shares system RAM; native macOS Ollama is outside Docker limits. Model size,
context length and concurrent inference determine Ollama's separate requirement.

## Apply the settings

The root Compose file uses the overrides in the table. The three
[TrueNAS examples](../../truenas/README.md) expose the same backend, Temporal,
PostgreSQL, UI and web limits as named values under `x-settings`. Keep the Go
soft targets below their corresponding container caps. Redeploy/recreate the
affected containers after changing YAML; restarting an existing container does
not change its resource configuration. Ordinary recreation retains data.
For an existing deployment, merge the resource settings into its deployed YAML
and preserve its coordinated image references. The example image pins are not
an instruction to downgrade a newer installation.

The native backend does not inherit Compose settings. To set its soft target
when running directly, export `GOMEMLIMIT=1536MiB` in its environment. That is
not a host-enforced limit. Do not change Temporal's history-shard count on an
existing database to reduce RAM.

Temporal also retains workflow state in caches. The Go soft target does not
evict live cache entries. If a large import leaves Temporal close to its budget,
measure its retained state and review the pinned server's cache settings before
increasing concurrency. This investigation preserves those settings; the RAM
recommendations do not guarantee capacity for arbitrary workflow histories.

## Collect evidence on the affected host

Find the Compose project and check Docker's current working-set view:

```sh
docker ps -a --format 'table {{.Names}}\t{{.Label "com.docker.compose.project"}}\t{{.Status}}'
docker stats --no-stream
```

From a checkout with the pinned Bun and Task tools, record the exact project
name (TrueNAS usually supplies a different name from `domabas`):

```sh
task diagnose:memory -- --project=domabas --duration=1800 --interval=5
```

The command reads the selected Docker context; it never starts, stops or
deletes containers. It writes a new `.logs/memory-<timestamp>.jsonl` file and
excludes Ollama from the displayed totals while retaining its measurements.
It only measures containers in that project. Native Go/Air, Flutter, browsers,
native Ollama and the host itself require separate host process monitoring.
Use `--output=PATH` to choose a new output file. It requires Linux cgroup v2
with `memory.peak` support and `cat` inside the images. Unsupported counters
are marked as missing rather than interpreted as zero. Partial totals are
explicitly marked `INCOMPLETE`. Samples are sequential observations, not an
atomic snapshot of the whole host.

Each sample records container identity, image reference/ID, configured cap,
running state, start/finish times, exit code, restart count, `OOMKilled`,
current/peak cgroup bytes, anonymous memory,
file cache, shared memory and cgroup OOM counters. `sharedBytes` is included in
`fileBytes`; do not add them together. Working set subtracts `inactive_file`
from current bytes, matching Docker's Linux CLI convention. If a racing cache
counter is at least current usage, the working set uses current bytes unchanged.
Raw current usage includes cache/kernel charges and is not Go live heap. Peaks and OOM
counters belong to that container's cgroup lifetime; compare IDs across
recreation. A stopped container may no longer expose counters, so keep samples
and inspect failure state promptly.

For a host without Bun, select the exact failed container name:

```sh
docker inspect CONTAINER --format 'OOMKilled={{.State.OOMKilled}} Exit={{.State.ExitCode}} Restarts={{.RestartCount}} Memory={{.HostConfig.Memory}}'
docker exec CONTAINER cat /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.peak /sys/fs/cgroup/memory.events
docker logs --since 30m CONTAINER
```

On the Linux/TrueNAS host, also check `journalctl -k --since "30 minutes ago"`
for a host OOM kill and `free -h` for available memory. Use available memory,
not only free memory: Linux can reclaim much of its filesystem cache. Container
counters alone cannot explain a Docker VM or host crash. Exit code 137 means
SIGKILL, which also occurs without OOM.

Measure a warmed idle period, repeat the same workload at least three times,
then allow completed jobs to drain between batches and after the final batch.
Record document dimensions/pages, concurrency, models, failed jobs and latency.
Run longer than the original time to failure when possible. Compare each
service's post-idle anonymous/working-set baseline and cgroup peak, not just
the host total. Caches can grow to a plateau; persistent growth under a fixed
workload warrants private Go heap profiles and inspection of retained objects.
A brief plateau cannot rule out a slower or input-specific leak.

For a crash while answering an AI question, start recording before submitting
the question and continue through completion or failure. Record the backend
image tag/digest, chat model, turn status, document/chunk counts, number of
consecutive searches and whether ingestion was active. Inspect the backend,
Temporal and PostgreSQL separately
even when Ollama remains healthy. The failed container's evidence determines
whether its own limit or host pressure was involved; a healthy Ollama container
does not identify which other service failed.

In the current implementation, chat limits each turn to 30 document/catalog
tool calls, reads document text in 8,000-character pages and caps model context
at 48,000 characters. Provider responses are limited to 128 KiB. Temporal
workflow/activity payloads carry turn identifiers, while conversation and tool
contents live in PostgreSQL. These bounds reduce the risk of one question
retaining an entire document corpus in application memory. They do not rule out
leaks or behavior in older releases. See the [chat architecture](../arch/backend/ai-chat.md).

See the [testing guide](testing.md) for repeatable checks and required services.
These measurements are optional operator diagnostics; regular CI runs the
sampler's parser tests without requiring Docker or starting a soak test.

Sources: [Docker resource limits](https://docs.docker.com/engine/containers/resource_constraints/),
[Docker stats accounting](https://docs.docker.com/reference/cli/docker/container/stats/),
[Go memory-limit guidance](https://go.dev/doc/gc-guide), and
[Linux cgroup v2 memory counters](https://docs.kernel.org/admin-guide/cgroup-v2.html).
See also [Linux memory accounting](https://docs.kernel.org/filesystems/proc.html).
