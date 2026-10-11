# Application screenshots

These screenshots show the running Domabas web app in light appearance.
All documents, accounts and email addresses shown are fictional.

## README product tour

| Screenshot | View |
| --- | --- |
| [Document grid](document-grid.png) | Eight processed PDFs with thumbnails and tags, plus search and filter controls. |
| [Invoices](invoices.png) | Three extracted CII invoices with suppliers, invoice numbers, issue and due dates, and totals. |
| [Library members](library-members.png) | A shared library with Owner, User and Viewer access. |
| [Processing job](job-pipeline.png) | A completed document ingestion job showing extraction, embeddings and search indexing. |

All images are 1440 × 1040 browser captures. They do not show native apps.

## Prepare and capture

Keep the product tour short and focused on populated feature views. Use an
isolated application instance with a disposable database schema, unique Temporal
queues and separate storage/key directories. Upload fictional documents through
the real API and wait for processing to finish. Use Playwright MCP to inspect and
capture the running app. Do not mock UI state or retouch images.

Review every image before adding it here and to the
[README](../../readme.md#screenshots). Label responsive web and native captures
accurately. Keep local demo credentials and process details in the ignored
`docs/plans/` directory. Stop only owned processes and remove only their disposable
data when the demo is no longer needed.
