# Configure property extraction

Open Admin → Document processing, select Property extraction, and enable it.
Changes apply to every library and queue the normal reindex of retained originals.
Existing titles and populated properties stay unchanged. Empty description, tags,
sender, recipients, date and subject can be filled from OCR. Check extracted data
when using it: a model can infer an incorrect value.

Extraction requests all six fields and instructs the model to return `null` for
unknown or ambiguous facts instead of inventing data. Such values leave metadata
empty. A required output field does not require a guessed value, and existing
populated properties remain unchanged.

Choose Internal Ollama and keep `qwen3.5:4b`, or enter another model name. The first
job that needs an absent model downloads it into the persistent Ollama cache.
Jobs shows the property extraction stage while this happens. A slow download may
exhaust the bounded job deadline; retry the failed job after the cache is ready.
Disabled extraction does not download or call a language model. The default
Compose Ollama memory ceiling is 8 GiB to accommodate the optional model; idle
memory is not preallocated. Larger models may require more memory or a GPU.
The runtime allows two loaded models so Qwen and the embedding model can serve
the same ingestion workload. Its bounded request queue defaults to 128; set
`OLLAMA_MAX_QUEUE` to change that capacity. Queue capacity does not increase
processing concurrency or the existing request deadlines.

For an external provider, choose External service and enter its complete API base
URL (for example `https://models.example.com/v1`) and model name. Enter a bearer
API key if needed. It is encrypted in PostgreSQL; reopening the form shows only
whether a key is stored. Leave the key field empty to retain the key, enter a new
one to replace it, or remove it explicitly. Changing provider or URL removes the
old credential. Enabling an external provider sends a bounded prefix of document
OCR text to that service. It must implement non-streaming chat completions and
JSON object responses.

## Server configuration

| Setting | Default | Purpose |
| --- | --- | --- |
| `LLM_OLLAMA_URL` | `http://127.0.0.1:11435` for native development; `http://ollama:11434` inside Compose | Internal Ollama origin |
| `LLM_OLLAMA_PORT` | `11435` | Compose's loopback-only published port for native Go development |
| `LLM_CREDENTIAL_KEY_FILE` | `.secrets/llm.key` under document storage; `/var/lib/domabas/secrets/llm.key` in Compose | Automatically generated private persistent encryption key |
| `LLM_CREDENTIAL_KEY` | Empty | Optional base64-encoded 32-byte key injected by an operator |
| `OLLAMA_MEMORY_LIMIT` | `8g` | Ollama host memory ceiling |
| `OLLAMA_MAX_QUEUE` | `128` | Maximum queued Ollama requests |

Back up the credential key volume together with PostgreSQL. Losing this key makes
retained provider credentials unreadable. Startup fails instead of silently
generating a replacement while encrypted records exist. An ordinary Compose
shutdown retains keys, files, database and models. For several backend instances,
share the key file or inject the same key into each instance.

## NVIDIA CUDA

For `task dev`, set `OLLAMA_RUNTIME=cuda` in `backend/.env`. For packaged Docker
deployments, use the commands below. The development selector also accepts
`cpu`, `rocm` and `mlx`; see the
[runtime guide](compose.md#select-the-development-ollama-runtime).

Install the NVIDIA driver and NVIDIA Container Toolkit on a supported Docker host,
then use the committed override:

```sh
docker compose -f compose.yaml -f compose.cuda.yaml up --build --wait
```

The override requests all NVIDIA GPUs. The base pinned Ollama image supports CUDA.

## AMD ROCm

Use a Linux host with a supported AMD GPU and ROCm driver:

```sh
docker compose -f compose.yaml -f compose.rocm.yaml up --build --wait
```

This override selects the pinned ROCm image and maps `/dev/kfd` and `/dev/dri`.
The official image currently targets x86-64. GPU passthrough through Docker on
macOS is not provided by these overrides. Both overrides retain the model volume.
Use the same `-f` arguments for subsequent Compose operations.

See the official [Ollama Docker guide](https://docs.ollama.com/docker) and
[GPU support guide](https://docs.ollama.com/gpu) for supported hardware and host
driver prerequisites. These overrides require their respective hardware to test.

## Apple Silicon MLX

Set `OLLAMA_RUNTIME=mlx` in `backend/.env` and restart `task dev`. The launcher
downloads a verified native Ollama runtime and connects the Docker processor to
its retained native cache. Choose Internal Ollama and an MLX-compatible model
such as `gemma4:12b-mlx` in Admin → Document processing. The runtime setting does
not rewrite saved model choices. Nomic embeddings keep their pinned model and
verification; they are not converted to MLX. See the
[development runtime guide](compose.md#select-the-development-ollama-runtime).
