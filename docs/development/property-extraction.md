# Configure property extraction

Open **Admin → Document processing** with the system processing permission. Property and invoice AI default to off and can be enabled independently. Both use the same administrator-configured external connection. Chat has its own connection under **Admin → AI chat**.

Enter the provider's full OpenAI-compatible API base URL, such as `https://models.example.com/v1`, its model identifier and an optional bearer key. The URL must be reachable from the Go backend. For a service hosted outside Docker, use an address reachable from the backend container. Leave the key blank to retain an existing credential at the same destination. Changing the endpoint clears its credential unless you supply a replacement.

Enable **LM Studio compatibility mode** for extraction providers that require named JSON schema output. The default requests JSON object output. The endpoint must support non-streaming chat completions. Set thinking for property and invoice extraction independently according to the provider and model's supported reasoning modes. The provider controls context length. Save the settings and enable the desired features. Enabled document AI sends a bounded prefix of OCR text to the configured endpoint. Chat sends the user's question and authorized content retrieved by its tools.

## Server configuration

| Setting | Default | Purpose |
| --- | --- | --- |
| `LLM_CREDENTIAL_KEY_FILE` | `.secrets/llm.key` under document storage, or `/var/lib/domabas/secrets/llm.key` in Compose | Persistent encryption key for stored credentials |
| `LLM_CREDENTIAL_KEY` | Empty | Optional base64-encoded 32-byte key supplied by the operator |

Back up the key with PostgreSQL and use the same key across backend replicas. The app preserves stored external settings during an upgrade. Installations that used internal generation must configure an external service before re-enabling those features. Local embeddings, OCR and structured invoice XML remain available with generation disabled. For optional embedding GPU acceleration see [CPU and Vulkan setup](compose.md#select-the-embedding-runtime).
