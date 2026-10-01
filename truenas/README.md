# Domabas on TrueNAS

These complete Docker Compose examples target **TrueNAS 25.10 (Goldeye) and
later**. They include the web app, backend, PostgreSQL, Temporal, Ollama and
document processing. Follow the steps below, then paste one complete file into
**Apps > Discover Apps > Install via YAML**.

This guide is for NAS operators. For a small home library, start with **4 CPU
cores and 5 GiB available RAM**, plus memory for Ollama models, TrueNAS and other
apps. You also need a dedicated dataset and usable Domabas image references as
described below. A GPU and HTTPS proxy are optional.

[Choose a file](#1-choose-a-file) · [Storage](#2-prepare-the-dataset) ·
[Settings](#3-fill-in-your-settings) · [GPU setup](#4-check-your-gpu-on-the-host) ·
[Deploy](#5-deploy-the-app) · [Backups and updates](#update-and-back-up)

## 1. Choose a file

| File | Ollama runtime | Dataset path to set | Default web / Temporal UI ports |
| --- | --- | --- | --- |
| [compose.cpu.yaml](compose.cpu.yaml) | CPU; no GPU access | `/mnt/POOL/domabas` | `8088` / `8233` |
| [compose.cuda.yaml](compose.cuda.yaml) | NVIDIA/CUDA | `/mnt/POOL/domabas` | `8088` / `8233` |
| [compose.rocm.yaml](compose.rocm.yaml) | AMD/ROCm | `/mnt/POOL/domabas` | `8088` / `8233` |

Each file is standalone. No override files, `.env` files or local builds are
needed. All three files use the same storage preparation and run every service
as **UID/GID `950:950`**.

**Public GitHub image references will follow.** The examples currently use
`example.invalid/replace-me/domabas-<component>:REPLACE_WITH_RELEASE` placeholders
for the initializer, backend, document processor and web app. These placeholders
cannot be pulled or deployed. Before deploying, replace the whole `image` value
in `x-init`, `services.backend`, `services.document-processor` and `services.web`
with real, matching release versions and digests from a registry your NAS can
access. Keep the `x-init` anchor so all initialization services share its image.
The examples require `linux/amd64` images. If your chosen registry requires
authentication, configure it under **Apps > Configuration > Sign-in to a Docker
registry**. For a deployment built from a checkout, use the
[Compose guide](../docs/development/compose.md). Maintainers can find container publishing and version selection in the
[release guide](../docs/development/releases.md). No native app downloads are published.

## 2. Prepare the dataset

For an existing installation, first read [Adopt older storage](#adopt-older-storage).

1. In TrueNAS, create a dedicated dataset such as `POOL/domabas`. Use the actual
   pool name and capitalization. The corresponding host path is
   `/mnt/POOL/domabas`.
2. Set the dataset owner and group to the accounts with numeric UID/GID
   `950:950`. If these IDs are unused, create a dedicated user and group with
   these IDs in TrueNAS first. If already assigned, confirm they belong to the
   intended app account. Ensure UID `950` can traverse the parent path, create
   directories in this dataset and change their permissions.
3. Use private application storage permissions. Inherited share ACLs must allow
   the initializer to apply the private modes below.
4. Set `dataset_path` at the top of the YAML to this existing absolute path.

Check the parent path in the **TrueNAS host shell or over SSH**:

```bash
stat -c '%n mode=%a uid=%u gid=%g' /mnt/POOL/domabas
```

Replace `POOL` before running it. A missing parent path must be corrected in
TrueNAS before deployment. The YAML deliberately does not create the parent.

The `storage-init` service creates six ordinary directories, then applies these
modes before storage consumers start:

| Directory inside `dataset_path` | Container location | Owner | Mode |
| --- | --- | --- | --- |
| `postgres` | PostgreSQL `/var/lib/postgresql` | `950:950` | `0700` |
| `ingestion` | Backend `/data/ingestion` | `950:950` | `0700` |
| `documents` | Backend `/data/documents` | `950:950` | `0700` |
| `secrets` | Backend `/var/lib/domabas/secrets` | `950:950` | `0700` |
| `tesseract` | Processor `/models/tesseract` | `950:950` | `0700` |
| `ollama` | Ollama `/home/ollama/.ollama`; processor `/models/ollama` read-only | `950:950` | `0755` |

You do not need to create these six directories for a new installation. The
initializer does not create ZFS datasets, change owners or recursively modify
existing files. It rejects directory roots owned by another UID, symlinks and
non-directory paths. Existing descendants and inherited ACLs need separate
attention if they prevent access.

The `domabas-storage` Docker volume points to the selected host dataset. Each
service mounts only its required subdirectories. Keep the container paths and
subdirectory names unchanged. Ollama's `HOME` and `OLLAMA_MODELS` settings keep
its cache writable as user `950`; the processor sees the same models read-only.
Temporal's `USER` setting and the web service's temporary writable directories
also match this user.

## 3. Fill in your settings

Keep the published templates unchanged. From the checkout root, make a private
copy of your chosen variant before entering credentials. This POSIX-shell
example selects CPU; use `cuda` or `rocm` in both names for a GPU variant:

```sh
(
  umask 077
  set -eu
  set -C
  cat truenas/compose.cpu.yaml > truenas/compose.cpu.local.yaml
  chmod 600 truenas/compose.cpu.local.yaml
)
```

The copy command refuses to overwrite an existing file. Files named
`*.local.yaml` or `*.local.yml` are ignored by Git and excluded from Docker build
contexts. Verify the exclusion with
`git check-ignore truenas/compose.cpu.local.yaml` (adjust the variant if needed).
Keep completed YAML and its backups private; do not force-add them or
attach them to issues. On other systems, restrict the file to your own account.

In the private copy, replace the image placeholders described in step 1, then
edit `x-settings` at the top. Leave the YAML anchor names (`&...`) and references
(`*...`) intact.

| Setting | What to enter |
| --- | --- |
| `dataset_path` | Existing dataset path from step 2 |
| `postgres_admin_password` | PostgreSQL provisioning password |
| `postgres_password` | Separate password for the Domabas database role |
| `temporal_password` | Separate password for the Temporal database role |
| `public_origin` | Browser HTTP or HTTPS origin, such as `http://192.168.0.230:8088` or `https://documents.example.com`; include a non-default port if used, with no path or trailing slash |
| `web_bind_address`, `web_port` | NAS address and host port reached by your browser or proxy; `0.0.0.0` binds all IPv4 interfaces |
| `temporal_ui_bind_address`, `temporal_ui_port` | NAS address and host port for Temporal UI |
| `temporal_ui_url` | Browser-reachable Temporal URL; update the NAS address and port or use a separate HTTPS hostname |
| `ingestion_concurrency` | Legacy setting retained for release compatibility; default `1`. Current source builds use Admin settings → Workload limits instead. |
| `ollama_max_queue` | Ollama queue budget; default `128`. Keep it consistent across Ollama, backend and processor. Current source builds require at least `2` and limit shared Ollama jobs to half this value. |
| `gpu_render_gid`, `gpu_video_gid` | ROCm example only: numeric GPU device group IDs from step 4 |

All three passwords start empty and must be filled. Generate a different password
for each role with a password manager; 64-character hexadecimal passwords avoid
YAML and interpolation escaping. Never reuse the checked-in development defaults
from `backend/.env` or the main Compose file. Compose expands dollar signs
even in quoted YAML: write `$$` for a literal `$`. For example, `abc$$def`
delivers `abc$def`. Preserve `$$POSTGRES_USER` in the PostgreSQL health check.

Check your private copy without printing resolved credentials:

```sh
docker compose -f truenas/compose.cpu.local.yaml config --quiet
```

Use the matching filename for CUDA or ROCm. This validates syntax only; empty
passwords and placeholder images must still be replaced before deployment.

Open Domabas directly at `http://<NAS-address>:<web_port>`, for example
`http://192.168.0.230:8088`, and set `public_origin` to that exact origin.
Browser sign-in and installed apps support this HTTP address. HTTP does not
encrypt traffic. To use HTTPS, point your proxy at the same HTTP address; the
proxy must preserve the original Host and Origin and support WebSocket upgrades.
Set `public_origin` to the HTTPS origin when using the proxy.

Temporal UI opens the `domabas` namespace. **Admin > Document processing >
Temporal dashboard** uses `temporal_ui_url`. Replace the fictional hostname
`nas.example.test` in the default URL with your browser-reachable NAS hostname
or address. Changing the published port also requires updating this URL. Use
an address reachable from your browser, not a container name or localhost.

Temporal UI has unauthenticated cluster administration access. Domabas sign-in
does not protect its port; keep it on a trusted network or behind an
authenticated proxy. PostgreSQL, Temporal gRPC, Ollama and the processor have
no published host ports.

## 4. Check your GPU on the host

Run the commands in this step in the **TrueNAS host shell or over SSH**, before
installing. CPU users can skip to step 5.

### AMD / ROCm

First, identify the GPU behind each render device:

```bash
ls -l /dev/kfd /dev/dri/

for node in /sys/class/drm/renderD*; do
  printf '\n%s\n' "/dev/dri/$(basename "$node")"
  lspci -Dnnk -s "$(basename "$(readlink -f "$node/device")")"
done
```

Look for your AMD GPU and `Kernel driver in use: amdgpu`. `/dev/kfd` must also
exist. If a required device is missing, investigate host GPU/driver support
before changing container permissions.

Next, get the numeric device group IDs:

```bash
stat -c '%n mode=%a uid=%u gid=%g group=%G' \
  /dev/kfd /dev/dri/card* /dev/dri/renderD*
```

Example device permissions:

| Device | Mode | Owner | Group |
| --- | --- | --- | --- |
| `/dev/kfd` | `660` | root (`0`) | render (`107`) |
| `/dev/dri/renderD128` | `660` | root (`0`) | render (`107`) |
| `/dev/dri/card0` | `660` | root (`0`) | video (`44`) |

These IDs are examples, not universal defaults. Set `gpu_render_gid` and
`gpu_video_gid` in `compose.rocm.yaml` to your host's values. The example already
passes them to Ollama through `group_add`. If `/dev/kfd` has a different owning
group from the render node, add that numeric GID to `group_add` as well.

With those example group IDs, the ROCm configuration resolves to these Ollama settings:

```yaml
    user: "950:950"
    group_add:
      - "107"
      - "44"
    devices:
      - /dev/kfd:/dev/kfd
      - /dev/dri:/dev/dri
```

Mapping devices makes them visible; supplemental groups grant the non-root
process permission to use them. Use host numeric GIDs because group names
inside the image can differ. See [Docker group settings](https://docs.docker.com/reference/compose-file/services/#group_add).

Mapping `/dev/dri` exposes all its GPUs. If you need only one, identify its
render node above, then replace that directory mapping with, for example,
`/dev/dri/renderD128:/dev/dri/renderD128`. Keep `/dev/kfd:/dev/kfd`.
Recheck the node after hardware changes. See [AMD device mapping](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/how-to/docker.html).

Leave `HSA_OVERRIDE_GFX_VERSION` unset initially. It changes the architecture
reported to ROCm, not which GPU is selected.
Automatic detection is the starting point, not a guarantee of compatibility
with every host driver. See [AMD specifications](https://rocm.docs.amd.com/en/latest/reference/gpu-specs.html)
and [Ollama hardware support](https://docs.ollama.com/gpu).

### NVIDIA / CUDA

Enable NVIDIA drivers in TrueNAS and check host detection:

```bash
nvidia-smi -L
```

Use a GPU supported by the installed TrueNAS driver and Ollama. Check the
[TrueNAS 25.10 GPU notes](https://www.truenas.com/docs/scale/25.10/gettingstarted/versionnotes/#nvidia-gpu-support)
for that release's driver requirements.

The CUDA example gives Ollama `gpus: all`. To select one NVIDIA GPU, replace
that setting with its UUID from `nvidia-smi -L`:

```yaml
    gpus:
      - driver: nvidia
        device_ids: ["GPU-YOUR-GPU-UUID"]
```

Only Ollama receives GPU access in either GPU example. The CPU example has no
GPU mapping or device groups.

## 5. Deploy the app

1. Open **Apps > Discover Apps > Install via YAML** from the menu.
2. Enter an app name such as `domabas`, paste the entire completed private copy
   and save.
3. Wait for storage, database and Temporal initialization, then model preparation.
   Successful one-shot initialization services exit normally; they do not keep
   running. First startup may download models and take several minutes.
4. Check service logs if the app does not become ready. Open your configured web address
   and register the first account. On an empty installation, it becomes system
   administrator.

When changing `group_add`, device mappings or environment settings, edit and
save the installed app's YAML so TrueNAS redeploys it. Restarting the old
container alone does not apply a changed container configuration.

### Upgrade an existing PostgreSQL 18 installation

Newer Domabas releases require pgvector 0.8.6 for document search. The PostgreSQL
service must use the same pinned image as the main Compose file:

```yaml
    image: pgvector/pgvector:0.8.6-pg18-trixie@sha256:78bf48b801e792f99e3ac62b5036fd3876e9be48afda16c1e331af1c75ceb2ff
```

If database initialization reports `extension "vector" is not available`, the
running PostgreSQL image lacks the extension files. Retrying initialization with
the old `postgres:18.6` image cannot fix it. pgvector's
[Docker image](https://github.com/pgvector/pgvector#docker) adds these files to
PostgreSQL; the pinned image above retains PostgreSQL 18.6.

1. Stop the app and take a consistent database backup or snapshot.
2. Edit the installed app's YAML. Replace `services.postgres.image` with the value
   above and use matching initializer, backend, processor and web images from the
   chosen release. Set `services.backend.healthcheck.start_period` to `10m`, as in
   the current examples, so Docker allows time for startup migrations. Keep the
   existing dataset path, `postgres` subdirectory,
   `/var/lib/postgresql` mount, user IDs and passwords.
3. Save and redeploy so TrueNAS recreates PostgreSQL with the new image and reruns
   `database-init`. The updated initializer enables `vector` in the application
   database as its administrator, including on retained storage.
4. Wait for initialization and backend startup to finish. Migration 029 builds
   the search index from existing embeddings; larger libraries take longer.

Keep the existing database directory and volume. No data reset or re-embedding
is required. See the [Compose upgrade notes](../docs/development/compose.md) for
migration timing and externally managed PostgreSQL.

If TrueNAS reports that the `up` action failed, inspect the backend and PostgreSQL
logs and the matching failure in `/var/log/app_lifecycle.log` on the host. The
generic deployment error does not identify which service failed. An older backend
health check with `start_period: 10s` can mark the service unhealthy before its
migrations finish, preventing the web service from starting. The `10m` grace
period permits slow migrations without delaying a backend that becomes ready
sooner. It does not extend the backend's own ten-minute startup deadline.

If the backend and web containers remain `Created`, inspect the document processor
first: backend startup waits for processor health. Use the TrueNAS host shell when
the UI cannot display its logs (replace the container name if your app has another
name):

```bash
sudo docker logs --timestamps --tail 100 ix-domabas-document-processor-1
sudo docker inspect ix-domabas-document-processor-1 --format 'Restarts={{.RestartCount}} OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}'
```

A `create PDF compilation cache: mkdir /app/tmp/...: permission denied` error
means the processor is using the image's private scratch directory, owned by UID
`65532`, while TrueNAS runs it as UID `950`. Keep `TMPDIR: /var/tmp` under
`services.document-processor.environment`, as in the current examples, then save
and redeploy. This uses disk-backed scratch writable by the configured user;
individual job and PDF cache directories remain private. Existing documents,
database files and model caches need no ownership changes.

Index build time depends on the number of embedded text chunks and available
CPU, memory and storage speed. Document count alone cannot predict it. During
the build, a database administrator can inspect progress in the application
database:

```sql
SELECT pid, phase, blocks_done, blocks_total,
       round(100.0 * blocks_done / nullif(blocks_total, 0), 1) AS percent
FROM pg_stat_progress_create_index;
```

An empty result means no index build is currently reported; check backend logs
to distinguish successful completion from failure or a wait before index creation.
See [pgvector index progress](https://github.com/pgvector/pgvector#indexing-progress)
and [Docker startup health checks](https://docs.docker.com/reference/dockerfile/#healthcheck).

## 6. Verify container access and actual GPU use

Find the running Ollama container from the **TrueNAS host shell**:

```bash
sudo docker ps --filter label=com.docker.compose.service=ollama \
  --format 'table {{.Names}}\t{{.Image}}'
```

Choose the container belonging to your Domabas app and set its exact name:

```bash
OLLAMA_CONTAINER='replace-with-container-name'
```

Inspect its configured user, groups and GPU mappings:

```bash
sudo docker inspect "$OLLAMA_CONTAINER" \
  --format 'User={{.Config.User}} Groups={{json .HostConfig.GroupAdd}} Devices={{json .HostConfig.Devices}} GPURequests={{json .HostConfig.DeviceRequests}}'
```

For AMD, check access as the actual configured user. Do not override it to root
for this check:

```bash
sudo docker exec "$OLLAMA_CONTAINER" sh -c '
id
ls -ln /dev/kfd /dev/dri/
for device in /dev/kfd /dev/dri/renderD*; do
  if [ -r "$device" ] && [ -w "$device" ]; then
    echo "ACCESS OK: $device"
  else
    echo "ACCESS FAILED: $device"
  fi
done
'
```

Expect UID/GID `950:950`, your added groups and `ACCESS OK` for `/dev/kfd` and
the intended render nodes. Permission checks establish file access; model
execution is the next check. For NVIDIA, check container visibility with:

```bash
sudo docker exec "$OLLAMA_CONTAINER" nvidia-smi -L
```

Trigger model processing in Domabas, then run:

```bash
sudo docker exec "$OLLAMA_CONTAINER" ollama ps

sudo docker logs --tail 300 "$OLLAMA_CONTAINER" 2>&1 \
  grep -Ei 'rocm|hip|gpu|gfx|offload|permission|denied|error'
```

Read the `PROCESSOR` column: `100% GPU` means the loaded model is entirely on
the GPU; a CPU/GPU split means partial offload; `100% CPU` means CPU-only.
Empty output means no model is currently loaded. CPU-only is expected for the
CPU example. See the [Ollama FAQ](https://docs.ollama.com/faq#how-can-i-tell-if-my-model-was-loaded-onto-the-gpu).

The `ollama list` health check proves the service responds, not that inference
uses the GPU. If devices are accessible but inference stays on CPU, inspect
the logs for the selected GPU, architecture, driver errors and available memory.

## Resources

Start with four CPU cores and **5 GiB of available RAM** for a small home library,
plus memory for Ollama models when using AI. Include the search embedding model
even when optional AI is disabled. Add capacity for TrueNAS, ZFS and other apps.
Large documents, bulk imports and higher concurrency need more headroom; this
starting recommendation does not cover every simultaneous service peak.

The examples cap PostgreSQL, Temporal and the backend at 2 GiB each, the
processor at 4 GiB, Temporal UI at 256 MiB, web at 512 MiB and Ollama at 8 GiB.
Temporal and the backend use a 1536 MiB Go soft target; UI uses 192 MiB. Edit
the named limits and targets under `x-settings`, then redeploy the app. These
are ceilings, not idle usage or memory reservations.

The processor's 2 GiB `/tmp` tmpfs shares its container budget when used;
these examples set `TMPDIR=/var/tmp` for disk-backed OCR and PDF compilation
scratch writable by UID `950`. The image's default `/app/tmp` is private to UID
`65532` and must not be used with the TrueNAS user override. An integrated GPU shares
system RAM. See the [resource guide](../docs/development/resources.md) for
the complete budget, scratch requirements and commands to identify OOM kills
and record memory during repeated imports or AI chat turns.

Start with one admitted Ollama job. On current source builds, set this in
**Admin settings → Workload limits**; the legacy `ingestion_concurrency` field
does not control the shared scheduler. Adjust resources before increasing
capacity or choosing larger models. See [resource scheduling](../docs/arch/backend/resource-scheduler.md).
The processor health check allows ten minutes for initial preparation; retained
caches avoid repeated downloads.

## Adopt older storage

Older examples used six separate `*_path` settings and container users such as
root, PostgreSQL UID `999` and application UID `65532`. The current files use
one `dataset_path` and UID/GID `950:950` throughout.

1. Stop the existing app and take a consistent snapshot or backup of all six
   stores and the completed YAML before changing ownership or paths.
2. Locate the existing `postgres`, `ingestion`, `documents`, `secrets`,
   `tesseract` and `ollama` stores. They must appear under the selected dataset
   with those names. If the old paths were elsewhere, prepare a storage
   migration while the app is stopped; changing YAML does not move files.
3. In TrueNAS, correct ownership to `950:950` for those stores and their
   existing contents, including PostgreSQL's nested data and saved secret keys.
   Preserve file permissions within them; do not apply one directory mode to
   every file. Resolve incompatible inherited ACLs on this app's storage.
4. Preserve the existing passwords, image versions, ports and public origin.
   Keep the Ollama cache contents: its container path changes from
   `/root/.ollama` to `/home/ollama/.ollama`, but its host `ollama/models`
   directory remains the same.
5. Redeploy and repeat step 6. If initialization reports an ownership mismatch,
   correct the indicated path in TrueNAS. The initializer only checks and
   adjusts the six directory roots; it does not migrate their descendants.

Keep `dataset_path` unchanged during routine updates. Relocating an existing
bind-backed Docker volume is a separate migration; do not assume editing that
setting updates an already-created volume's driver options.

## Update and back up

Keep PostgreSQL, ingestion, documents and secrets together in backups. Losing
the secrets directory prevents decryption of saved integration credentials.
Retain model caches to avoid downloading them again.

Read [Data and privacy](../docs/development/privacy.md) for the stored data,
chat key location, external AI sharing, deletion limits and log protection.

For a consistent backup, stop the app, confirm its containers have stopped,
then snapshot all stores and retain the completed YAML and image references.
Restore all stores from the same backup point. Ordinary shutdown preserves
data; do not delete the dataset or volumes as routine troubleshooting.

To update application images, use coordinated release references for `x-init`,
`backend`, `document-processor` and `web`. Replace the whole `image` value,
including its digest. Retain your dataset path, passwords, user and group IDs,
ports, origin and GPU settings. Keep Temporal server/schema-tool versions
matched. PostgreSQL major upgrades require a separate migration; reverting an
image does not necessarily undo a schema migration.

Changing `postgres_admin_password` in YAML does not rotate that password in an
existing database. Keep it unchanged unless performing a deliberate rotation.

Maintainers should update all three examples together when changing shared
setup or image pins. These files are not rewritten by
release CI. Validate each with `docker compose -f FILE config --quiet`.
Syntax validation does not establish successful NAS startup or GPU inference.
Runtime verification remains a separate step. The [testing guide](../docs/development/testing.md)
explains which checks establish syntax, compilation and actual runtime behavior.

See also the [Compose operations guide](../docs/development/compose.md),
[TrueNAS custom app instructions](https://apps.truenas.com/managing-apps/installing-custom-apps/)
and [Ollama Docker setup](https://docs.ollama.com/docker).
