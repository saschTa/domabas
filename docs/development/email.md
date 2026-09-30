# Email configuration

Email import uses password or app-password authentication to a verified implicit
TLS IMAP server, normally on port 993. OAuth enrollment, plaintext IMAP and STARTTLS
are not supported. Each provider imports into its selected library. Defaults are
15 minutes between completed scans, a maximum age of 30 days and 50 messages per
page; the owner can change these independently.

## Automatic credential keys

Email accounts need no server key setup. On first backend startup, Domabas
creates a random 32-byte key in a private file at
`DOCUMENT_STORAGE_ROOT/.secrets/email.key`. Later startups reuse that file.
For native development, the default location is `.cache/documents/.secrets/email.key`
from the repository root. `EMAIL_CREDENTIAL_KEY_FILE` optionally changes the path.
The email key is separate from the Paperless key.

Compose stores the key at `/var/lib/domabas/secrets/email.key` in the retained
`credential_keys` volume. Ordinary container recreation and down/up preserve it.
Start `task dev` or `docker compose up --build --wait`, then add your IMAP account
in User settings. No generated secret belongs in the checked-in `backend/.env`.

The backend writes and syncs a complete private temporary file before publishing
it exclusively, so concurrent startup cannot replace a key or read partial data.
Unix key files have mode 0600; their parent directory must not permit group or
public writes. Symlinks, malformed keys and insecure permissions are rejected.
Windows deployments must protect the directory with operating-system ACLs.

Keep this file with installation backups, separately protected from database
backups. Replicas using one database must share the same key file or explicit
keyring. Both usernames and passwords are encrypted. If a key file is missing
while encrypted providers remain, or the automatic key cannot decrypt them,
startup fails with a recovery message instead of generating a replacement.
Restore the original key file or the previous explicit keyring. If the key is
lost permanently, an operator can supply a new explicit keyring and each owner
must replace both mailbox credentials; the old credentials cannot be recovered.

## Explicit keyrings and rotation

Existing deployments can keep `EMAIL_CREDENTIAL_KEYS` and
`EMAIL_CREDENTIAL_ACTIVE_KEY_ID`. When either is supplied, explicit configuration
takes precedence and the automatic file is not read or created. Both must be
valid: the first is a JSON object mapping key IDs to base64-encoded random
32-byte keys; the second selects its active member. Up to eight keys are allowed.
Key IDs contain 1–32 letters, digits, underscores or hyphens. Partial or invalid
configuration fails startup without printing key material.

To move from automatic management to an explicit keyring, include the existing
file's base64 value under the key ID `automatic`. Keep that entry until rotation
has replaced every retained envelope that needs it. Do not generate a different
key under the same ID. Once credentials use other key IDs, retain the explicit
keyring rather than returning to the single automatic key file.

Generate additional key material locally, for example:

```sh
bun --no-env-file -e 'console.log(Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString("base64"))'
```

Store explicit settings in an ignored `.env.email.local` or deployment secret
injection system. Export that file before `task dev`, or pass it to Compose with
`docker compose --env-file .env.email.local up --build --wait`. Bun tooling does
not load it automatically. Exported settings override `backend/.env`.

To rotate, add a new key, make it active and retain the old read keys. Bounded
maintenance rewraps unchanged provider credentials without altering import consent
or overwriting concurrent edits. Remove an old key only after no stored envelope
uses it and retained backups no longer require it. Deleting a provider removes its
recoverable secret; accepted documents remain in their library.

Using an operator database connection in the application's schema, count envelopes
by key ID after the restarted backend has run its maintenance loop:

```sql
SELECT credential_key_id, count(*) AS remaining_envelopes
FROM email_providers
WHERE credential_ciphertext IS NOT NULL
GROUP BY credential_key_id
ORDER BY credential_key_id;
```

Wait until the old key has no remaining envelopes before removing it from the
running keyring. Rotation uses compare-and-swap against the saved envelope and
credential version, so a concurrent owner edit wins; provider revision, source
generation and consent do not change merely because the envelope was rewrapped.
The query exposes counts and key identifiers only, never decrypted credentials or
ciphertext.

## Private servers and TLS

`EMAIL_IMAP_CA_FILE` optionally points to a PEM CA bundle added to the backend's
system roots. Hostname verification remains enabled. In containers, mount the file
read-only and use its container path; do not modify the host's trust store.

For example, an ignored `compose.email.local` override can mount an operator-owned
CA bundle:

```yaml
services:
  backend:
    environment:
      EMAIL_IMAP_CA_FILE: /run/email/ca.pem
    volumes:
      - ./mail-ca.pem:/run/email/ca.pem:ro
```

Apply it with `docker compose --env-file .env.email.local -f compose.yaml -f
compose.email.local up --build --wait`. Keep the CA file outside version control
when it identifies private infrastructure.

`EMAIL_IMAP_ALLOWED_HOSTS` is an optional comma-separated exact hostname allowlist
(for example, `mail.example.test,imap.internal.example.test`). Without it,
ordinary DNS names resolving to public unicast addresses are permitted. Private,
loopback and link-local destinations require an explicit allowlist entry.
Unspecified and multicast addresses are rejected. A configured allowlist limits
connections to its entries, so include each intended provider host. This also
makes disposable local TLS mailbox tests possible without disabling verification.

The owner supplies a host or strict `imaps://host` endpoint, an explicit port and a
separate mailbox name. URL credentials, paths, queries and fragments are rejected.
Connection tests use read-only mailbox selection, return sanitized results and do
not import mail or change Seen flags.

## Processing and recovery

Imports continue while a provider is enabled, including after browser logout.
Changing the Domabas account password invalidates background consent; use Renew
consent and save after signing in again. Disabled membership or missing required
library claims also prevents new acceptance. Already accepted documents follow
ordinary library access and retention.

Raw EML is retained unchanged within the 100 MiB original limit. Supported PDF,
PNG and JPEG attachments become ordinary documents. Unsupported or damaged parts
have explicit outcomes; a raw email can remain available even when text extraction
fails. The Jobs view distinguishes retrieval from later document processing.
Increasing maximum age starts bounded backfill while live mail continues to scan.

Backend and private processor must be updated together for the EML extraction
manifest. Retained older PDF/image processing snapshots stay supported. Do not
reset database volumes or edit applied migration files during rollout.

Tests use disposable schemas, task queues, storage and a TLS IMAP fixture with its
own CA. No real mailbox password or OS trust-store change is required. See the
[testing guide](testing.md) and [email architecture](../arch/backend/email-ingestion.md).
