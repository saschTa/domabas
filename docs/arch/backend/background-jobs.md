# Background jobs

Record ownership and job intent in the same PostgreSQL transaction as the operation that accepts work. Domain services validate permissions, revisions and cancellation before publishing results. The native executor resumes durable work and drains on shutdown.

See [worker lifecycle](native-jobs.md) and [resource scheduling](resource-scheduler.md).

## History totals

The document, email and Paperless history pages include bounded grouped totals
for Jobs filter pills. Each source counts the complete history under its existing
read authority, independently of page cursors and selected status or pipeline.
Document totals retain namespace and optional document scope; email totals retain
owner, namespace and optional provider scope; Paperless totals retain owner and
namespace scope. Counts use typed SQL group rows, including retained deleted
source history. Paperless effective status treats a successful run with failed
items as partial completion. No aggregate grants access beyond its history list.

## Verification

Run `task test:jobs` for worker restart recovery and `task test:integration` for database ownership and resource contention.
