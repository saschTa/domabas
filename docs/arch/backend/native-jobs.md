# Native background workers

The Go API commits job intent in the application database. Domain services admit work in a transaction with the shared scheduler. A dedicated PostgreSQL session elects one executor per application schema. Other API replicas serve traffic and can take over work.

The executor polls the document, email, Paperless and chat ledgers. Each run has a stable identity, a next step, an attempt count and an outcome in `native_executions`. A completed checkpoint survives process restarts. A step interrupted between an external call and its checkpoint can run again. Domain writes check the document generation, owner, revision or attempt before publishing a result. Original files, credentials and model responses do not enter the execution checkpoint.

The worker checks its leadership connection independently of work discovery. A new leader advances the execution epoch and clears abandoned stage permits. Closing the application cancels operations and waits for running Go jobs before closing the database. Readiness includes the native worker, PostgreSQL, realtime listener and document processor.

## Upgrading from Temporal

Pause new submissions and scheduled imports, let admitted jobs finish with the previous deployment, and stop every old backend before starting the new version. Migration 041 refuses to cut over while any domain records an open admitted execution. Queued, unclaimed jobs remain eligible for the native worker. Keep the existing application database and document volumes. Previous Temporal history remains in its original databases.

See [resource scheduling](resource-scheduler.md) for the two levels of concurrency control.
