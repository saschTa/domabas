# Identity, namespaces and system administration

An account is the storage and API name for a document namespace. Every local user
has one personal namespace and can belong to other namespaces by invitation.
Registration creates the user, personal account, owned membership and session in
one transaction. Login selects the personal account; an invited membership being
disabled does not block access to the personal library. Email addresses are plain
ASCII addresses, trimmed and lowercased, with global uniqueness. Registration does
not verify mailbox ownership.

## Roles, claims and ownership

Roles bundle registered claims. Namespace roles and system roles have separate
scopes even when both are named `admin`.

| Namespace role | Initial claims |
| --- | --- |
| Admin | `documents:read`, `documents:create`, `documents:upload`, `documents:update`, `documents:download`, `documents:search`, `documents:retry`, `users:manage` |
| User | `documents:read`, `documents:create`, `documents:upload`, `documents:update`, `documents:download`, `documents:search`, `documents:retry` |
| Viewer | `documents:read`, `documents:download`, `documents:search` |

Document metadata vocabulary requires the conjunction of `documents:read` and
`documents:search`, under the existing registered document claims. Its HTTP guard
and vocabulary service both enforce that conjunction for the current library.
Ordinary document search remains independently available with `documents:search`.
System administration alone does not grant either library capability.

A membership may add known namespace claims to its role bundle. Grants are
additive; there are no deny overrides or editable custom roles. The system `admin`
role grants `system:users:manage` and `system:document-processing:manage`; system
`user` grants no administration claim.
All three namespace roles also include `realtime:connect`. It permits the live
connection; each emitted topic still requires its underlying feature authority.
See [realtime authorization](realtime.md) for fresh session and membership checks.
System administrators can list users and change system roles. This authority
never supplies membership or access to another user's documents.

Ownership is separate from a role. Personal owners and retained historical owners
receive every registered namespace claim. **Every new feature must define its
scoped claims, enforce them at its entry points, and grant its namespace claims to
owners by default.** Unknown strings, wildcard values and system claims are not
included in ownership. Feature tests must cover owner defaults, role bundles,
delegated grants and denial. Ordinary member and invitation operations cannot
create, transfer, disable or edit ownership.

One immutable catalog and Casbin v3.11.0 policy define the effective claims. The
identity container injects the evaluator into services and the shared HTTP guard.
Feature services use consumer-owned identity authority ports to load current
facts, ignoring caller-provided roles and permissions. Data sources return raw
facts and atomically compare mutation preconditions; they contain no claim
selection or policy evaluator. See [service policy and persistence](service-policy-and-persistence.md). Catalog access returns fresh values; there is no mutable
policy database or global collection callers can modify.

An actor with `users:manage` can create, invite or update non-owner members only
when the proposed role-plus-grants union is a subset of its current namespace
claims. A viewer given member-management access cannot use it to grant document
creation. Namespace inputs reject unknown, duplicate, wildcard or system claims.
Membership and invitation grants are bounded arrays of at most 32 IDs, each at
most 64 UTF-8 bytes. PostgreSQL enforces array shape, size and non-null elements;
application policy owns the evolving allowlist. Unknown stored grants are denied.

The canonical contract represents claim IDs as strings. Flutter keeps immutable
string sets, known action constants and scoped catalog descriptors. Adding a
backend claim does not make an older client fail to decode identity responses.
The server remains responsible for deciding whether an input claim is known.
Catalog descriptors also return the role names that contain each claim, scoped
by the descriptor. These are extensible strings mapped directly from the same
catalog used for authorization. Forms display the union of role claims and
explicit grants, while saving explicit grants separately; an inherited check is
not an extra grant and an existing explicit grant retains its provenance.

## First administrator and retained installations

Migration 003 records whether users, accounts and documents are all absent.
Registration locks this durable singleton and gives system administrator access
only to the first successful registration on that empty installation. Bootstrap
eligibility is consumed in the same transaction and is not restored by later
emptiness or restart. Concurrent registrations cannot create two first admins.
System-role changes serialize on the same row and cannot remove the final admin.
Each system-user list response includes `adminCount` across the entire
installation, even when the requested page contains no administrators. It is
read inside the existing authorized installation transaction. Clients use the
snapshot to explain and disable final-admin demotion, and refresh it after role
changes or conflicts. The snapshot is advisory; the mutation transaction remains
responsible for preventing concurrent removal of the final administrator.

Retained users are not promoted automatically. An operator with configured
database access can explicitly designate an existing user when no system admin
exists:

```sh
task db:bootstrap-admin -- --user-id USER_UUID
# Or with the packaged stack:
docker compose exec backend /app/bootstrap-admin --user-id USER_UUID
```

The command applies migrations, uses a bounded transaction, consumes any remaining
bootstrap eligibility, and refuses once an administrator exists. It has no public
HTTP equivalent and startup does not run it. Select the user deliberately; the
command is an installation recovery operation, not a normal promotion endpoint.

Migration 003 preserves account IDs, documents, credentials, memberships, enabled
flags and existing sessions. Old `owner` becomes namespace `admin` plus ownership;
old `editor` becomes `user`. The earliest enabled old owner by creation time and
user ID keeps that account as its personal library. Every other retained user gets
an empty personal account while retaining previous access. A disabled historical
owner stays disabled in the old library. If no owner is enabled, no user reuses
that library as a personal account. A deferred composite foreign key guarantees
that every personal-account selection has a matching membership.

## Invitations and membership

A namespace manager issues an invitation for a canonical email, role and explicit
grants. The server returns a random 32-byte Base64URL code once to the issuer and
stores only its SHA-256 digest. The code expires after seven days. The issuer
copies and delivers it outside Domabas; there is no outbound email service.

Acceptance requires both a signed-in user with the matching email and possession
of the code. A self-asserted email alone cannot reveal or accept an invitation.
Lists show metadata and status, never codes or digests; there is no recipient
inbox that exposes secrets. Acceptance submits the code in a bounded POST body,
never a URL. Invalid, foreign, expired, revoked and replayed codes receive the
same unavailable response. Failed attempts do not consume a valid code.

The acceptance service checks the current enabled issuer, management claim
and delegation ceiling, then inserts the membership and consumes the invitation
atomically. Existing memberships, including disabled ones, are never overwritten
or reactivated. Acceptance does not switch the active library. Managers can list
and revoke invitations without recovering the code.

The previous local-member creation endpoint remains available. It creates the
new user's personal namespace and requested shared membership together; the
initial password must be changed before normal use. Existing emails remain a
conflict. The regular UI uses invitations so managers do not create or share
another user's password. No user-management operation changes another person's
email or resets their password.

## Passwords, sessions and HTTP guards

Passwords use the pinned Argon2id wrapper v1.0.0 and `x/crypto` v0.57.0, with
64 MiB, three passes, four lanes, 16-byte salts and 32-byte outputs. At most two
derivations run simultaneously. A started derivation holds its permit until it
finishes because Argon2 is not cancellable. Stored parameter bounds are checked
before verification. Unknown users receive equivalent dummy-hash work.

New passwords contain 8–128 Unicode characters and at most 512 UTF-8 bytes; they
are never trimmed or truncated. A small common-password denylist supplements
these bounds, without claiming comprehensive breached-password coverage. Login
checks credentials independently of this new-password policy. Password change
requires the current password and revokes every session across all namespaces.

Sessions use random 32-byte canonical Base64URL tokens, with only SHA-256 digests
stored. New sessions have a null deadline, meaning no routine application expiry.
Migration 005 makes the session deadline nullable without rewriting existing
finite deadlines. Authentication, locked identity operations and document upload
transactions accept null deadlines and still reject expired finite deadlines.
Session writes return the row stored by PostgreSQL, including its microsecond
timestamp precision. Registration, login and namespace switching use these stored
values so exact session-fact comparisons reject changes without mistaking lost
sub-microsecond precision for a concurrent update.
Exactly one Authorization bearer header is accepted on protected APIs; cookies
and URL tokens are ignored there. Every request reads the current
membership, ownership, grants, system role and credential revision. Role, grant
or enabled changes revoke the affected namespace sessions; system-role changes
revoke the target user's sessions. Protected responses use `Cache-Control: no-store`.

Namespace switching verifies the old session and destination membership under
locks, inserts a new bearer for the destination, and deletes the old bearer in
one transaction. The new session keeps the exact original nullable expiry. Independent
sessions keep their own active namespaces. Concurrent switches of one bearer
have at most one winner. The old token's account is never mutated in place.

Shared guards authenticate and authorize before generated body/path/query decoding.
Only current identity, password change and logout accept sessions that still need
an initial password change. Catalog, namespace, invitation and administration
operations require password completion. Document handlers obtain account IDs from
the private principal context and pass them explicitly to application services.
No body, query or header can override document scope. Health/readiness and local
register/login are public. See [HTTP presentation](http-presentation.md).

Credential work retains process-local limits: 240 operations per minute globally,
60 per minute per direct source address, and 20 per 15 minutes per operation/email.
There are at most 10,000 expiring buckets. Invitation work also uses bounded
limiting before capability lookup. Forwarded addresses are not trusted. Limits
reset on restart and are not shared across replicas. At issuance, a separate
bounded transaction removes at most 200 expired sessions with skip-locked rows;
cleanup failure cannot undo successful authentication.

Flutter restores persisted credentials through the API before displaying protected
state. The browser stores persistence in an HttpOnly cookie; native clients use
secure credential storage. TLS termination is required outside local development.
Mailbox verification, password
recovery and MFA are not implemented. The
[frontend identity guide](../frontend/identity.md) explains the corresponding
account, library and session flows.

## Browser and native session restoration

`POST /api/v1/auth/restore` returns the same bearer with current identity and its
original nullable deadline. The authority and deadline come from one query;
stored client identity never supplies permissions. Native clients pass their
persisted bearer explicitly. Browser clients send `X-Domabas-Browser: 1`, include
credentials, and send no Authorization header. Only this endpoint reads a cookie
as a credential. An absent browser cookie returns 204. Invalid, expired, revoked
or ambiguous browser credentials return 401 and clear the cookie. Infrastructure
failure preserves the cookie for retry.

Browser registration, login, switching, restoration, password change and logout
require a single valid Origin matching the request authority (including port) or
an exact configured CORS origin. The marker must be exactly `1`. This validation
precedes session issuance and cookie mutation. CORS allows credentials and the
marker only for configured exact origins. Native requests without the marker
retain ordinary bearer behavior and receive no cookies. Browser GET requests do
not require Origin, since browsers can omit it for reads that do not mutate
persistence.

HTTPS uses `__Host-domabas_session` with Secure, HttpOnly, SameSite=Strict, Path=/
and no Domain. HTTP is supported on IP addresses and hostnames, using
`domabas_session` with the same restrictions except Secure. The validated Origin
determines HTTPS even when a TLS proxy connects to Go over plaintext. Forwarded
headers do not grant trust. The nginx proxy preserves the original Host and port.
Frontend and API must share a site; use the same loopback hostname on both when
developing across ports. HTTP does not encrypt credentials or documents in transit.

Successful registration, login, switching and restore set the cookie. Its lifetime
is at most 400 days, reduced to any retained finite session deadline, and renewed
on restore. Browsers can evict it or clear it at the user's request. Successful
password changes clear it and revoke all sessions. Valid browser logout clears
it before bearer authentication so an already-revoked token also loses persisted
state; a blocked origin cannot clear it. Server-side revocation remains necessary
when logout cannot reach the service. Cookies are not a defense against active
same-origin script compromise, and tokens never belong in URLs or localStorage.

New persistent sessions survive ordinary restarts and expiry cleanup; cleanup
removes only expired finite rows. Logout and the existing credential, membership
and system-role revocations still delete affected sessions. Deploy the new
nullable-session API and client together. See
[persistent session storage](../frontend/platforms.md#persistent-session-storage)
for browser and native credential handling.

## Transactions and document isolation

The data source owns each complete transaction. Account, member, invitation and
system-user lists use read-only repeatable-read transactions for page contents and
counts. Services validate current identity and session before those scoped reads,
without locking account, user, membership, session or bootstrap rows. Authority
and content do not necessarily share one snapshot; an already authorized operation
may finish after concurrent revocation. Realtime retains its facts snapshot and
interprets it before emission. See the explicit
[operation boundary](service-policy-and-persistence.md#operation-boundaries-and-revocation).

Security-sensitive mutations retain explicit locks for credential/session
issuance, revocation, namespace switching, invitation delegation and acceptance,
and first/last-administrator invariants. Their lock acquisition follows:
installation singleton when needed, account rows sorted by ID, user rows sorted
by ID, memberships, acting session, then invitation. Discovery reads do not grant
authority. The service evaluates permission and relationship facts first; after
locks, the source compares those facts and enforces expiry/consume-once fences.
Switching includes both accounts. Acceptance includes the session and invitation
accounts and recipient/issuer users. No operation acquires another account after
a user lock. User-wide revocation shares the user locking discipline with session
creation, switching and password changes.

Login verifies Argon2 before the transaction and rechecks its verified hash and
credential revision under locks before issuing a session. System writers recheck
the acting administrator after acquiring the singleton. These rules prevent stale
credentials, stale grant delegation and concurrent final-admin removal. Ordinary
requests already authorized may finish after revocation. Every later service
operation rechecks authority, including upload acceptance after streaming and each
meaningful stage of background work. Provider, run and item fences still enforce cancellation and
ownership. Client generation checks prevent old results from entering a
replacement namespace's UI. Ordinary reads do not delay credential or membership
revocation.

Document create/get/list/count always require a validated explicit account ID.
SQL filters both rows and count by that account; a foreign document ID returns
404. Generated Jet types stay in data adapters. Sessions retain the composite
membership foreign key, and repositories have no unauthenticated fallback.

## Legacy documents and deployment

Migration 002 leaves older unowned documents quarantined with null ownership.
They remain invisible to every namespace and system administrator. An operator
can explicitly adopt them into an existing account:

```sh
task db:adopt -- --account-id ACCOUNT_UUID
docker compose exec backend /app/adopt-legacy --account-id ACCOUNT_UUID
```

Use the intended account UUID from the authenticated identity. Adoption validates
and locks the account and updates only still-unassigned rows in a bounded
transaction. Repeating it cannot move already owned documents. Startup never
adopts automatically and no HTTP endpoint exposes this operation.

Deploy the new server and client together for the new role vocabulary. Old
unscoped service/worker binaries must not run with the scoped schema. Temporal v2
metadata work carries account/document IDs and scoped activity reads. The retained
v1 workflow keeps its original command sequence for replay, while its activity
fails without reading unscoped documents. Completed history remains readable.

Document job history and namespace reindexing use independent namespace claims
`documents:jobs:read` and `documents:reindex`. The Admin role bundle and registered
namespace ownership grant both; other members need explicit grants. Either claim
can inspect namespace pipeline configuration and aggregate batch progress. Job
history does not imply document reading: current titles require `documents:read`.
The system processing claim grants aggregate installation orchestration and the
internal dashboard URL, without namespace job or document access.

`system:paperless:manage` permits installation-wide Paperless retrieval settings.
Only system administrators receive it; namespace owners and namespace admins do
not. The settings service checks the live system role and session before both
reads and optimistic-revision writes. Managing this setting does not require
namespace Paperless import or document permissions.
