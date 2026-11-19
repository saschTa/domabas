# GitHub releases

Releases start manually from **Actions → CI and releases → Run workflow**.
Select `main` and a version increment. The run publishes four images, an Android
preview APK and a macOS DMG in one
GitHub release after the [required checks](testing.md#github-actions) pass in a
`push` run on `main` for that exact commit. The manual release reuses that run;
it builds apps, scans containers and publishes without repeating the test suites or OSV
source scan.
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
prefix. Third-party PostgreSQL and Ollama images keep their existing
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
advances while publication runs. It verifies a successful `push` run of `ci.yml`
on `main` with the same commit SHA before creating a tag, draft or image build.
If main CI is missing, running or failed, wait for it to succeed and retry the
manual release. No test rerun is started by the publisher. Release notes link to
the reused main run. It rejects automatic events and non-main refs.
PR labels do not select versions. See GitHub's
[manual workflow documentation](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
for access requirements and dispatch options.

Versions below 1.0.0 are marked as GitHub prereleases. Moving to 1.0.0 should be
an intentional support decision. There is no floating `latest` container tag;
use the explicit version or digest from the release notes.

The [quick-start Compose file](../../compose.quickstart.yaml) currently pins the published v0.0.10 images. Update its four Domabas image references together when promoting a release and verify anonymous pulls. The generic Compose in each release’s notes comes from the root `compose.yaml`.

Release packaging also attaches standalone `compose.cpu.yaml`, `compose.cuda.yaml` and `compose.rocm.yaml` assets for TrueNAS. It substitutes that release’s four immutable image references into the [source templates](../../truenas/README.md), preserving the editable anchors and hardware configuration. The source templates use local tags for deployments built from the checkout.

## Publication and retries

Version reservation and final publication share a lock using GitHub's
[concurrency queue](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).
Up to 100 pending jobs are retained. They run in queue arrival order,
which can differ from commit order when releases are requested at different times.
If that limit is exceeded, rerun cancelled manual release runs. PR cancellation
does not cancel releases.

The preparation job reserves a version with a Git tag at the exact tested commit
and creates a draft release. Android and macOS build in parallel after preparation
releases the lock. Both use the reserved version and the workflow run number as
their build number. The publication job waits for both builds and takes the same
lock. It verifies each downloaded artifact's commit, version, build number, size
and SHA-256 hash, then uploads both files and `SHA256SUMS.txt` to the draft.
Upload receipts must match the expected size and hash before container work starts.

It builds the four `linux/amd64` images with Docker
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
images and native downloads; matching uploaded files are reused. Successful native
jobs retain their current-run artifacts for 14 days, so rerunning failed jobs can
reuse those downloads. If artifacts have expired, rerun all jobs. Published
retries skip native builds, container builds and publication. Do not move or delete reserved
release tags: the publisher rejects changed tags, mismatched commits and
ambiguous versions. Reserved but unfinished releases can leave version gaps.
A later manual release can publish after an older release failed. GitHub releases
are not promoted through a mutable latest pointer.

The preparation job has five minutes. Each native job has 60 minutes including
setup and a 45-minute build command deadline. The final publication job has
60 minutes including setup, with a 50-minute command deadline.
Docker reuses layers within the job; this initial workflow does not promise a
warm Docker cache across hosted runners. Credentials are kept in the ephemeral
runner's Docker configuration and restored after publication. They are never
Docker build arguments or container layers.

## Native preview downloads

Each new release includes:

| File | Contents |
| --- | --- |
| `domabas-v<version>-android-preview.apk` | Release-mode APK using the runner's development signing key |
| `domabas-v<version>-macos-universal-unsigned.dmg` | Intel and Apple silicon app, with an Applications shortcut |
| `SHA256SUMS.txt` | SHA-256 checksums for both downloads |

Android requires API 24 or later. Allow installation from the app used to open
the downloaded APK. A new hosted runner generates a different development key,
so updating may require uninstalling the previous app first. Uninstallation
removes local app data, including saved sessions and unfinished scanner drafts;
documents already stored on the server remain there. These APKs are previews,
not Play Store releases, and have no stable signing identity.

macOS requires version 12 or later. Open the DMG and drag `domabas.app` to
Applications. There is no Developer ID signing or Apple notarization. The app
retains the ad hoc signature needed on Apple silicon; the disk image is unsigned.
Gatekeeper may block opening it. Only for a download you trust, use macOS
**System Settings → Privacy & Security → Open Anyway** if offered. See
[Apple's guidance](https://support.apple.com/en-us/102445). No signing secrets
are required by either build.

Apps connect to an existing Domabas server; enter its address on first launch.
Compilation and packaging do not certify device behavior. Native binaries are
outside the container vulnerability scan. Native builds run only during manual
main releases; PR and main push jobs keep their shared Flutter tests.

Android uses GitHub's `ubuntu-latest` runner with its Android SDK and pinned Java
21. macOS uses the ARM64 `macos-15` runner with Xcode. The Flutter installer
verifies each host archive's checksum and the same pinned Flutter commit.
`task release:native -- android` or `task release:native -- macos` requires that
host's toolchain plus `RELEASE_VERSION`, `GITHUB_SHA` and `GITHUB_RUN_NUMBER`.
It writes the binary and its manifest under `.cache/native-release/<target>/`.
Use the [app build guide](build-apps.md) for ordinary local builds.

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
clean result. PR checks do not run this scan; main pushes do. Manual releases
reuse the source scan from the successful main run. Run `task security:dependencies`
locally to check new advisories between
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

This runs only in the manually triggered publication job on main, after verifying
the successful main CI run for its commit. PRs do not build or scan images. The job summary
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
(PostgreSQL and Ollama) are not built here and are outside this
four-image gate. Changes to those pins still need separate review. Future
scheduled scans of published digests can detect advisories disclosed between
releases; this workflow does not yet schedule them.

## Activate a new GitHub repository

1. Add the intended GitHub remote and publish a branch named `main`; set it as
   the default branch.
2. Enable GitHub Actions and permit the pinned actions in
   [the workflow](../../.github/workflows/ci.yml). Use GitHub-hosted
   `ubuntu-latest` and `macos-15`, not self-hosted runners. The first push runs checks.
3. Permit the release job's `GITHUB_TOKEN` to read Actions runs and write repository
   contents and packages. No personal access token or custom registry
   secret is needed. Rules protecting `v*` tags must allow this workflow to create
   them. PR jobs keep read-only permissions and do not persist checkout credentials.
4. Require **Fast checks** and **PostgreSQL integration** in the `main` branch
   ruleset before merging. Require PR review for workflow and release-tooling
   changes. Configure these rules after the first run makes check names available.
5. When ready to publish, open **Actions → CI and releases → Run workflow**,
   select `main` and the desired version increment. The publisher creates the
   release tag after verifying that main CI already passed for its captured commit.
6. Set each of the four GHCR packages to **Public** after first publication.
   GitHub packages can start private even for a public repository. Verify the
   repository is linked and its workflow can write each package. See
   [GitHub's registry permissions](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).
7. From a logged-out Docker configuration, pull all four release images and run
   a clean Compose install. Check each attached TrueNAS template against the release image digests. Refresh the quick-start pins when promoting the release. Verify hosted
   checks, publication, anonymous pulls and installation before advertising the
   release.

## Supported artifacts

| Target | Release artifact | Validation in this workflow |
| --- | --- | --- |
| Linux AMD64 deployment | Backend, web, processor and init containers | Fast source tests, PostgreSQL integration, image builds and critical-only image scans; complete deployment smoke is separate |
| Flutter web | Included in the web container | Dart analysis, VM/widget/repository tests and release compilation inside Docker |
| Linux ARM64 deployment | None | Not built or claimed |
| Android | Development-signed preview APK | Shared Dart tests from main; release compilation; device checks are separate |
| macOS Intel and Apple silicon | Unsigned, unnotarized DMG | Shared Dart tests from main; universal build, ad hoc signature and DMG integrity checks; device checks are separate |
| iOS, Linux/Windows desktop apps | None | Shared Dart tests only; native builds, signing and device checks are local |

The six Flutter source targets remain. Stable Android updates and store
distribution need a persistent release signing key and upgrade testing.
