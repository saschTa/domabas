# Application screenshots

These images show the running Domabas web application.
All accounts, email addresses and documents shown are fictional.

## README product tour

| Screenshot | View |
| --- | --- |
| [Document grid](document-grid.png) | Light appearance, four PDF previews and four email documents with tags; 1440 × 1200. The opening README image. |
| [Job pipeline](job-pipeline.png) | A completed email ingestion job with recorded timing and all processing stages; 1440 × 1040. |
| [Email setup](email-setup.png) | An unsaved IMAP setup example using `example.test`, with no password entered and no connection attempted; 1440 × 1040. |
| [AI settings](ai-settings.png) | The extraction settings dialog with both AI switches enabled as an unsaved example and the default local model; 1440 × 1040. |

## Additional views

| Screenshot | View |
| --- | --- |
| [Document library](document-library.png) | Light appearance, desktop list with searchable email documents and tags; 1440 × 1000. |
| [Document details](document-details.png) | Email content beside its properties; 1440 × 1000. |

## Refresh the screenshots

Use an isolated application instance with a disposable database schema, unique
Temporal queues and separate storage/key directories. Upload fictional documents
through the real API, wait for processing to finish, and capture the browser UI.
Do not mock UI state or retouch the images. Close unsaved settings
examples without saving them.

Inspect every image, then stop the owned processes and clean up only their
disposable data and workflows. Update the view descriptions above and the
[README captions](../../readme.md#screenshots) when the views change. Label web
and native captures accurately.
