# GitHub container releases

Releases start manually from **Actions → CI and releases → Run workflow**.
Select `main` and a version increment. The run publishes four images and one
GitHub release after the [required checks](testing.md#github-actions) pass.
Pull requests and pushes to `main`, including merges, run checks without publishing.
Manual runs on other branches or tags cannot publish. Image names come from the
GitHub repository:

```text
ghcr.io/<owner>/<repository>-backend:v0.0.1
ghcr.io/<owner>/<repository>-web:v0.0.1
ghcr.io/<owner>/<repository>-document-processor:v0.0.1
ghcr.io/<owner>/<repository>-init:v0.0.1
```

Owner and repository names are lowercased for GHCR. Git tags use the same `v`
prefix. Third-party PostgreSQL, Temporal and Ollama images keep their existing
pins and are not republished.

## Selecting the next version

Choose `release_bump` when starting the workflow. It defaults to `patch`; the
first patch release creates `v0.0.1`. The selected increment applies to the
highest existing semantic release tag or reserved release version:

| Version increment | Next version after `v0.2.7` |
| --- | --- |
| `patch` | `v0.2.8` |
| `minor` | `v0.3.0` |
| `major` | `v1.0.0` |

The workflow must be present on the repository's default branch before GitHub
offers **Run workflow**. Users with write access can also start a release with
GitHub CLI:

```sh
gh workflow run ci.yml --ref main -f release_bump=patch
```

The publisher uses the exact commit captured by the manual run, even if `main`
advances while checks run. It rejects automatic events and non-main refs.
PR labels do not select versions. See GitHub's
[manual workflow documentation](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
for access requirements and dispatch options.

Versions below 1.0.0 are marked as GitHub prereleases. Moving to 1.0.0 should be
an intentional support decision. There is no floating `latest` container tag;
use the explicit version or digest from the release notes.

The [quick-start Compose file](../../compose.quickstart.yaml) and
[TrueNAS examples](../../truenas/README.md) currently pin the published
[v0.0.10 images](https://github.com/saschTa/domabas/releases/tag/v0.0.10).
These pins are updated deliberately, not by each release job. Update all four
Domabas components together using the chosen release's tags and digests, verify
anonymous pulls, and update the versions documented in the README and hosting
guides. Keep the quick-start service configuration aligned with the root
`compose.yaml`, replacing its build definitions with image references and
`linux/amd64` platforms.

## Publication and retries

Publication is serialized using GitHub's
[concurrency queue](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).
Up to 100 pending release jobs are retained. They run in queue arrival order,
which can differ from commit order when checks take different amounts of time.
If that limit is exceeded, rerun cancelled manual release runs. PR cancellation
does not cancel releases.

The publisher reserves a version with a Git tag at the exact tested commit and
creates a draft release. It builds the four `linux/amd64` images with Docker
Buildx and the existing Dockerfile pins, then scans the local images with Trivy.
All four scans must pass before any image is pushed. Only after all pushes
return digests does it publish the release. Notes contain the commit, pull
commands and a complete Compose configuration pinned to those digests. Save the configuration as
`compose.yaml`, configure deployment passwords and addresses, then run
`docker compose up --wait`.

A failure can leave a reserved tag and draft. A registry failure after scanning
can also leave some image tags. Rerun the same workflow run to resume that
version. A later manual run for the same commit also reuses its reserved version,
even if a different increment is selected. Draft retries can replace incomplete
images; published retries skip builds and publication. Do not move or delete reserved
release tags: the publisher rejects changed tags, mismatched commits and
ambiguous versions. Reserved but unfinished releases can leave version gaps.
A later manual release can publish after an older release failed. GitHub releases
are not promoted through a mutable latest pointer.

The release job has 60 minutes including setup, with a 50-minute command deadline.
Docker reuses layers within the job; this initial workflow does not promise a
warm Docker cache across hosted runners. Credentials are kept in the ephemeral
runner's Docker configuration and restored after publication. They are never
Docker build arguments or container layers.

## Dependency vulnerability gate

`task security:dependencies` uses checksum-pinned
[OSV-Scanner v2.6.0](https://github.com/google/osv-scanner/releases/tag/v2.6.0).
It scans `backend/go.mod`, `frontend/pubspec.lock` and `bun.lock` with call
analysis disabled. These inputs are among OSV's
[supported formats](https://google.github.io/osv-scanner/supported-languages-and-lockfiles/).
There is no scanner subscription or API key; GitHub's ordinary Actions quotas
still apply to the runner.

Only **critical** findings block publication: a grouped CVSS score of at least
9.0 or an explicit critical advisory rating. High, medium, low and unscored
findings appear in the log and job summary without blocking. Download, checksum,
API and malformed-report failures fail the scan rather than masquerading as a
clean result. PR checks do not run this scan; main pushes and manual release runs
on main do. Run `task security:dependencies` locally to check new advisories between
releases without starting publication.

This is a dependency inventory scan, not proof of exploitability. It does not
scan container OS packages, statically linked OCR libraries, downloaded models
or native application binaries. The separate image gate below covers OS packages
and detectable libraries in the four built images.
Fix critical findings in a separate reviewed dependency PR and regenerate the
license inventory; do not suppress them just to obtain a release.

## Image vulnerability gate

Main releases use checksum-pinned [Trivy 0.74.0](https://github.com/aquasecurity/trivy/releases/tag/v0.74.0)
after building each first-party image. The release sequence is:

1. Build each `linux/amd64` image once and load it into the runner's Docker engine.
2. Scan its full immutable local image ID for OS and detectable library
   vulnerabilities. Verify that the scan report identifies that exact image.
3. After all four scans pass, push those same local images to GHCR. Verify that
   each tag still points to the scanned image before pushing.
4. Read the published digests and publish the GitHub release with those references.

A critical finding or scanner failure prevents every image push for that run.
Lower and unknown severity findings remain visible. Unfixed critical findings
also block; there is no automatic ignore list. Trivy uses its
[vendor-aware severity selection](https://trivy.dev/docs/latest/scanner/vulnerability/#severity-selection),
which accounts for distribution backports. The images are not rebuilt between
scanning and pushing. A later registry/network failure can leave some already
scanned images pushed while the GitHub release remains a draft.

This runs only in the manually triggered publication job on main, after its
source and database checks pass. PRs do not build or scan images. The job summary
shows severity counts and up to 100 findings per image, with critical findings first. Complete
JSON reports are retained as `image-vulnerabilities-<attempt>` workflow artifacts
for 14 days, including on failure. Scanning stops at the first failure; reports
exist only for images reached in that run. The Trivy database is cached across
release runs, including failed scans, with normal freshness checks enabled. A scan
has a ten-minute timeout within the release command's overall budget.

For a local image, inspect its full ID and pass it to the same scanner:

```sh
docker image inspect --format '{{.Id}}' <local-image-tag>
task security:image -- sha256:<full-image-id> --name backend
```

The task supports Linux x64 and macOS arm64, requires Docker access, and reads
only the requested local image. Reports are written to `.cache/image-scans/`.
It scans vulnerabilities only; it does not run the image or scan for secrets.
No paid scanner account or extra registry credential is needed.

Coverage depends on scanner support and package metadata. Trivy can detect Go
modules embedded in binaries, but custom statically linked OCR code and compiled
Flutter web dependencies are not comprehensively inventoried by this scan. OSV
remains required for source dependencies. Third-party Compose service images
(PostgreSQL, Temporal, Ollama and their UI) are not built here and are outside this
four-image gate. Changes to those pins still need separate review. Future
scheduled scans of published digests can detect advisories disclosed between
releases; this workflow does not yet schedule them.

## Activate a new GitHub repository

1. Add the intended GitHub remote and publish a branch named `main`; set it as
   the default branch.
2. Enable GitHub Actions and permit the pinned actions in
   [the workflow](../../.github/workflows/ci.yml). Use GitHub-hosted
   `ubuntu-latest`, not a self-hosted runner. The first push runs checks.
3. Permit the release job's `GITHUB_TOKEN` to write repository contents and
   packages. No personal access token or custom registry
   secret is needed. Rules protecting `v*` tags must allow this workflow to create
   them. PR jobs keep read-only permissions and do not persist checkout credentials.
4. Require **Fast checks** and **PostgreSQL integration** in the `main` branch
   ruleset before merging. Require PR review for workflow and release-tooling
   changes. Configure these rules after the first run makes check names available.
5. When ready to publish, open **Actions → CI and releases → Run workflow**,
   select `main` and the desired version increment. The publisher creates the
   release tag after that run's checks pass.
6. Set each of the four GHCR packages to **Public** after first publication.
   GitHub packages can start private even for a public repository. Verify the
   repository is linked and its workflow can write each package. See
   [GitHub's registry permissions](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).
7. From a logged-out Docker configuration, pull all four release images and run
   a clean Compose install. Keep the quick-start and TrueNAS examples aligned
   with the published image versions and digests. When using a fork, update their
   image references to that repository's matching image digests. Verify hosted
   checks, publication, anonymous pulls and installation before advertising the
   release.

## Supported artifacts

| Target | Release artifact | Validation in this workflow |
| --- | --- | --- |
| Linux AMD64 deployment | Backend, web, processor and init containers | Fast source tests, PostgreSQL integration, image builds and critical-only image scans; complete deployment smoke is separate |
| Flutter web | Included in the web container | Dart analysis, VM/widget/repository tests and release compilation inside Docker |
| Linux ARM64 deployment | None | Not built or claimed |
| Android, iOS, Linux/macOS/Windows desktop apps | None | Shared Dart tests only; native builds, signing and device checks are local |

The six Flutter source targets remain. Android's local release configuration
still uses development signing, so a future native distribution needs a stable
signing key and upgrade testing before publication.
