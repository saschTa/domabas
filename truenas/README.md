# Domabas on TrueNAS

These complete Docker Compose examples target **TrueNAS 25.10 (Goldeye) and
later**. They include the web app, backend, PostgreSQL, llama.cpp embeddings and the private document processor. The backend runs the Go background workers. Follow the steps below, then paste one complete file into
**Apps > Discover Apps > Install via YAML**.

The templates use volume subpaths supported by the required TrueNAS release.
Separate startup health-check intervals also require Docker Engine 25+ and
Compose 2.20.2+. Steady checks run every 30 seconds; see
[health-check behavior and backend image requirements](../docs/development/compose.md#health-checks).

You need a dedicated dataset and the Domabas images described below. The CPU
template runs OCR and embeddings on the NAS without a GPU. See [Resources](#resources)
for CPU limits and memory sizing alongside TrueNAS and ZFS.

[Choose a file](#1-choose-a-file) · [Storage](#2-prepare-the-dataset) ·
[Settings](#3-fill-in-your-settings) · [GPU setup](#4-check-your-gpu-on-the-host) ·
[Deploy](#5-deploy-the-app) · [Backups and updates](#update-and-back-up)

## 1. Choose a file

| File | Embedding runtime | Dataset path to set | Default web port |
| --- | --- | --- | --- |
| [compose.cpu.yaml](compose.cpu.yaml) | CPU | `/mnt/POOL/domabas` | `8088` |
| [compose.vulkan.yaml](compose.vulkan.yaml) | Linux Vulkan | `/mnt/POOL/domabas` | `8088` |

Each variant is standalone and uses UID/GID `950:950` with the same six storage directories.

**Published installations.** Choose the CPU or Vulkan asset from a release that includes llama.cpp. Each asset pins that release's four Domabas images by digest for Linux AMD64. Older releases require their own matching configuration.

**Testing this checkout before release.** The two templates in this directory use local image tags. On the Docker engine used by TrueNAS, build the four images from this checkout, or build them on another host and transfer them with `docker image save` and `docker image load`. From the repository root, run:

```sh
docker build --platform linux/amd64 -t domabas-init:native-local -f infra/init/Dockerfile .
docker build --platform linux/amd64 -t domabas-backend:native-local -f backend/Dockerfile .
docker build --platform linux/amd64 -t domabas-document-processor:native-local -f infra/document-processor/Dockerfile .
docker build --platform linux/amd64 -t domabas-web:native-local -f frontend/Dockerfile .
```

Public GHCR packages allow anonymous pulls. If the packages are private,
configure an account with package access under **Apps > Configuration > Sign-in
to a Docker registry** before deploying. Repository visibility and package
visibility are separate settings. For a deployment built from a checkout, use
the [Compose guide](../docs/development/compose.md). Maintainers can find manual
container publishing and version selection in the
[release guide](../docs/development/releases.md).

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
| `embedding` | Model initializer writes here. The embedding server and processor mount `/models/embedding` read-only. | `950:950` | `0755` |

You do not need to create these six directories for a new installation. The
initializer does not create ZFS datasets, change owners or recursively modify
existing files. It rejects directory roots owned by another UID, symlinks and
non-directory paths. Existing descendants and inherited ACLs need separate
attention if they prevent access.

The `domabas-storage` Docker volume points to the selected host dataset. Each
service mounts only its required subdirectories. Keep the container paths and
subdirectory names unchanged. The model initializer runs as UID 950 and validates the pinned GGUF.
The web service’s temporary writable directories also match this user.

## 3. Fill in your settings

Keep a private copy of the chosen template for your credentials. For a release installation, copy the downloaded release asset. For a source build, the following command copies the CPU template from the checkout root. Use `vulkan` for the GPU template.

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

In the private copy, edit `x-settings` at the top. Leave the YAML anchor names
(`&...`) and references (`*...`) intact.

| Setting | What to enter |
| --- | --- |
| `dataset_path` | Existing dataset path from step 2 |
| `postgres_admin_password` | PostgreSQL provisioning password |
| `postgres_password` | Separate password for the Domabas database role |
| `public_origin` | Browser HTTP or HTTPS origin, such as `https://documents.example.com`. Include a non-default port if used. Omit the path and trailing slash. |
| `web_bind_address`, `web_port` | NAS address and host port reached by your browser or proxy; `0.0.0.0` binds all IPv4 interfaces |
| `embedding_queue_size` | Embedding admission budget, default 128. Background slots are capped at half this value. |
| `render_device`, `render_group` | Vulkan only. Render node mapping and numeric owning group from step 4. |

Both passwords start empty and must be filled. Generate a different password
for each role with a password manager; 64-character hexadecimal passwords avoid
YAML and interpolation escaping. Never reuse the checked-in development defaults
from `backend/.env` or the main Compose file. Compose expands dollar signs
even in quoted YAML: write `$$` for a literal `$`. For example, `abc$$def`
delivers `abc$def`. Preserve `$$POSTGRES_USER` in the PostgreSQL health check.

Check your private copy without printing resolved credentials:

```sh
docker compose -f truenas/compose.cpu.local.yaml config --quiet
```

Use the Vulkan filename for GPU embeddings. This validates syntax only; passwords
and dataset settings must still be filled in, and the NAS must be able to pull
the images before deployment.

Open Domabas directly at `http://<NAS-address>:<web_port>` using your NAS
address and published port, and set `public_origin` to that exact origin.
Browser sign-in and installed apps support this HTTP address. HTTP does not
encrypt traffic. To use HTTPS, point your proxy at the same HTTP address; the
proxy must preserve the original Host and Origin and support WebSocket upgrades.
Set `public_origin` to the HTTPS origin when using the proxy.

Open **Admin settings → Workload limits** to inspect active jobs and set limits for ingestion, invoice extraction, tags, model calls, embeddings and Paperless retrieval. Only the web service publishes a host port.

## 4. Check your GPU on the host

For the CPU template, continue to deployment. The Vulkan template requires a working Linux Vulkan driver and an accessible GPU render node. In the host shell, inspect the available nodes and obtain the numeric group for the chosen GPU.

```sh
ls -l /dev/dri/renderD*
stat -c '%n %g' /dev/dri/renderD128
```

Set `render_device` to a host-to-container mapping of this node and set `render_group` to its numeric group. Only the embedding container receives GPU access. The public website and document processor use the same configuration as the CPU template.

## 5. Deploy the app

1. Open **Apps > Discover Apps > Install via YAML** from the menu.
2. Enter an app name such as `domabas`, paste the entire completed private copy
   and save.
3. Wait for storage and database initialization, then model preparation.
   Successful one-shot initialization services exit normally; they do not keep
   running. First startup may download models and take several minutes.
4. Check service logs if the app does not become ready. Open your configured web address
   and register the first account. On an empty installation, it becomes system
   administrator.

When changing `group_add`, device mappings or environment settings, edit and
save the installed app's YAML so TrueNAS redeploys it. Restarting the old
container alone does not apply a changed container configuration.

### Upgrade from a Temporal-based installation

Pause uploads and scheduled imports, let admitted jobs finish with the existing backend, then stop the old app and take a consistent dataset snapshot. Apply the matching native-worker template to the same app, retaining the dataset, credentials, origin and GPU settings. The migration checks for open executions and leaves queued work available to the new worker. If it reports an open execution, restart the previous stack to finish draining. Keep the old PostgreSQL data and credential keys. See [worker upgrade details](../docs/arch/backend/native-jobs.md).

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

Check that `model-init` completed and the document processor, embedding server, backend and web containers are healthy. Upload a small document, wait for searchable publication, then run a semantic search. On Vulkan installations, inspect the embedding service's startup logs for the selected GPU and the number of layers offloaded. Run the following in the host shell to locate its container.

```sh
sudo docker ps --filter label=com.docker.compose.service=embeddings
sudo docker logs --tail 200 EMBEDDING_CONTAINER_NAME
```

For permission errors, check the selected render node and its numeric group against your template. The CPU template uses the same GGUF model.

## Resources

Both templates set `cpus: 4` on `document-processor` and `embeddings`. If Docker
has fewer CPUs available, lower both values in your private YAML before deployment.

Allow memory for local OCR, PostgreSQL, the backend and embeddings alongside TrueNAS, ZFS and other apps. The templates limit PostgreSQL, the backend and embeddings to 2 GiB each, the processor to 4 GiB and web to 512 MiB. The total ceiling is 10.5 GiB. The Go soft target is 1536 MiB.

The processor's 2 GiB `/tmp` tmpfs shares its container budget when used;
these examples set `TMPDIR=/var/tmp` for disk-backed OCR and PDF compilation
scratch writable by UID `950`. The image's default `/app/tmp` is private to UID
`65532` and must not be used with the TrueNAS user override. An integrated GPU shares
system RAM. See the [resource guide](../docs/development/resources.md) for
the complete budget, scratch requirements and commands to identify OOM kills
and record memory during repeated imports or AI chat turns.

Start with one local embedding slot under **Admin settings → Workload limits**. External document AI and chat acquire independent provider slots. See [resource scheduling](../docs/arch/backend/resource-scheduler.md).
The processor health check allows ten minutes for initial preparation; retained
caches avoid repeated downloads.

## Adopt older storage

Older examples used six separate `*_path` settings and container users such as
root, PostgreSQL UID `999` and application UID `65532`. The current files use
one `dataset_path` and UID/GID `950:950` throughout.

1. Stop the existing app and take a consistent snapshot or backup of all six
   stores and the completed YAML before changing ownership or paths.
2. Locate the existing `postgres`, `ingestion`, `documents`, `secrets`,
   and `tesseract` stores. Keep these under the selected dataset with their existing names. If the paths differ, migrate the files while the app is stopped.
3. In TrueNAS, correct ownership to `950:950` for those stores and their
   existing contents, including PostgreSQL's nested data and saved secret keys.
   Preserve file permissions within them; do not apply one directory mode to
   every file. Resolve incompatible inherited ACLs on this app's storage.
4. Preserve the existing passwords, image versions, ports and public origin.
   Model initialization prepares the new `embedding` directory. The old model cache can remain in place. Configure an external provider to use generative AI.
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
ports, origin and GPU settings. PostgreSQL major upgrades require a separate migration; reverting an
image does not necessarily undo a schema migration.

Changing `postgres_admin_password` in YAML does not rotate that password in an
existing database. Keep it unchanged unless performing a deliberate rotation.

Maintainers should update all three examples together when changing shared
setup. Release packaging copies the three templates and replaces the local image tags with the digests from the same build. Validate each with `docker compose -f FILE config --quiet`.
Syntax validation does not establish successful NAS startup or GPU inference.
Runtime verification remains a separate step. The [testing guide](../docs/development/testing.md)
explains which checks establish syntax, compilation and actual runtime behavior.

See the [Compose operations guide](../docs/development/compose.md) and [TrueNAS custom app instructions](https://apps.truenas.com/managing-apps/installing-custom-apps/).
