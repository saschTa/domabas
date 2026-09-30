# Test fixtures

The email, LLM and Paperless fixture servers provide local, deterministic
responses for test harnesses. Their adjacent unit tests check fixture behavior.
The sample image below is shared by Compose smoke tests and Flutter tests.

[`invoice.png`](invoice.png) is a small, fictional invoice image used to check
the complete application. It was rendered with Go Regular using the same
fixture helper as the Go API and Temporal integration tests. It contains:

> Electricity invoice for household power
> Amount due is 240 euros.
> Payment requested before October.

The Compose smoke test uploads the image without copying these words into its
metadata. It then checks that text recognition makes the words searchable,
embeddings are created and the saved original matches the upload. See the
[test guide](../../../docs/development/testing.md) for the Compose smoke command.
