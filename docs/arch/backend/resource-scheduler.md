# Background resource scheduling

The application commits a worker slot and a pipeline slot together when admitting a durable job. Concurrent API processes share the same limits. Admission chooses the oldest feasible request. Running jobs keep their slots when an administrator lowers a limit.

| Work | Capacity used during execution |
| --- | --- |
| Document ingestion | Thumbnail rendering, OCR and embeddings in order. Embedding also needs the local Ollama provider. |
| Document enrichment | Invoice extraction and tag/property extraction can run concurrently. Each has its own limit and durable completion. |
| Invoice and tag inference | A language model slot and a slot for the actual provider origin, acquired together around each remote request. Structured invoice XML takes the local path. |
| Private chat | The model call uses the same language model and provider limits as document AI. |
| Paperless imports | The import-run cap limits simultaneous runs. A separate download cap counts outstanding item claims. Accepted files enter the ingestion queue. |
| Email retrieval | An admitted poll retrieves and imports messages. Document ingestion has its own budget. |
| Thumbnail backfill | Rendering shares its stage capacity with ingestion previews. |

The worker holds its pipeline slot while waiting for the next step. It releases stage permits when that operation ends. PostgreSQL serializes capacity checks and reservations, and database transactions finish before external I/O starts. Legacy combined ingestion jobs keep their original order for invoice and property processing.

System administrators open **Workload limits** to see active slots, edit parallelism and review which resources each pipeline uses. The live resource flow connects the selected pipeline to its resources. Each branch shows the slots held by that pipeline and the total across all pipelines. The same read counts reservations, active step permits and claimed Paperless downloads. Calls to an earlier provider configuration remain visible while active. The screen fetches a snapshot on entry and refreshes it when the WebSocket signals a committed change. Simultaneous changes share a refresh. Settings writes use a revision so concurrent edits can be detected. The workload and Paperless settings APIs share one download budget. Ollama retains its configured queue ceiling.

[Native worker lifecycle and upgrade instructions](native-jobs.md)
