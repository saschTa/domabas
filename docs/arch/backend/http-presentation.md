# HTTP presentation

The public contract remains `contracts/backend/openapi.yaml`. The generated
standard HTTP router registers every endpoint on one `http.ServeMux`; generated
request and response types stay at this boundary. Change the contract first when
adding an operation, run `task generate`, and commit both Go and Dart outputs.

## Domain ownership

Document and identity HTTP code live in `internal/presentation/<domain>`:

| Package | Responsibility |
| --- | --- |
| `models` | Handwritten request/response values and their validation methods |
| `handlers` | Generated HTTP operations, consumer-owned service port, status/error mapping |
| `routes` | One `Register` function, raw body predecoding and group middleware |

Identity's credential limiter is private to its routes package. Its bucket value
lives in a local model file. The shared identity error response and all its
visitor methods live together in the models package. Models do not import
handlers or routes.

The request models preserve required and optional fields and pagination defaults.
They use existing domain validation before invoking the service. Application
services retain their validation for callers outside HTTP. Output conversion maps
domain values directly to generated responses within the document handlers package, without
another copy of every generated response and error model. Empty list responses
contain an array, not `null`.

Root bootstrap constructs the document HTTP handler from the document container's
service. The root HTTP handler composes concrete document and identity handlers and implements shared
health/readiness operations. Its compile-time assertion against the generated
strict interface detects missing operations. The container and worker lifecycle
are unchanged; HTTP handlers do not own shared resources.

Root HTTP composition owns recovery, sanitized errors, security headers, CORS,
global OPTIONS responses, and the default ten-second request timeout. Readiness adds its
two-second deadline. Shared `transport` helpers own bounded JSON reads and error
encoding. They have no document field knowledge. Shared transport also holds injected authentication/permission guards and the private principal context key. Protected route groups run guards before generated decoding. Identity public routes and protected relative children are declared explicitly; see [identity](identity.md).

## Route groups

`routing.HTTPRouteGroup` declares a prefix, middleware, and child groups. These declarations
select middleware for generated patterns at construction time; they do not
register a second set of endpoints. Child prefixes begin with `/` and append to
their parent. Prefixes have no trailing slash, except for a top-level `/` group.
Overlapping groups must use the `Children` hierarchy. Duplicate prefixes and
unrelated overlapping groups fail during construction.

The document group declares a child `/{id}` with a further child `/content`,
giving `/api/v1/documents/{id}/content`. Upload and content routes override the
default 10 second deadline with 120 seconds. The `/search` child allows 30 seconds
for embedding and up to two ten-second database passes. Use the exact wildcard
names from the contract in group declarations. Document permissions select the trusted generated
method/path pattern, so uploads do not inherit the metadata-create claim.

Construction copies and flattens each group's inherited middleware. For each
generated pattern, the registration adapter chooses the deepest matching group
at an exact path or slash boundary. It applies that group's complete chain once:
parents enter before children, the first middleware declared enters first, and
exit order is reversed. Mutating the original declaration slices does not change
the constructed router.

The adapter registers the original method/path pattern unchanged. Runtime calls
`ServeMux.ServeHTTP` directly, preserving path wildcard values, GET/HEAD matching,
method errors, redirects, and escaped-segment behavior. There is no custom
runtime matching, prefix stripping, wildcard rebinding, or route rewriting.

## Adding a domain or nested group

1. Add operations to the canonical contract and regenerate both clients. Add
   domain presentation models, handlers and routes using the packages above.
2. Define the handler's consumer-owned service port. Implement generated strict
   methods and response mapping. Keep model methods with their defining types
   and raw JSON checks in routes.
3. Export one `Register` function from routes. Return the decorated ordinary
   generated server and its `[]routing.HTTPRouteGroup` together. Keep the separate
   decorator/group helpers private so root cannot omit validation by calling
   only one half. Identity registration also receives the clock and constructs
   one limiter for that router.
4. Have bootstrap inject the service into the handler. Root HTTP composes the
   strict handlers, calls document then identity registration once, combines the
   groups and calls generated endpoint registration once. Nested groups use
   relative prefixes and the contract's exact wildcard names. Preserve existing
   middleware ordering and add input/routing coverage.

## Request validation

The document module decorates the generated ordinary server before generated
strict decoding. Create, metadata update, search and configuration JSON accept
media-type parameters and use a 32 KiB envelope limit. OCR correction has a
12,587,008-byte envelope limit, then checks its decoded 2 MiB/2,048-chunk text
limits. OCR rejects unknown/duplicate fields, explicit nulls, trailing content,
malformed UTF-8 and unpaired surrogate escapes. Media-type, size and invalid-body
failures retain 415, 413 and 400 error envelopes. Upload uses its bounded multipart
reader and retry rejects any request body.

Search applies the same malformed-Unicode checks before generated decoding,
alongside its exact field/type allowlist and duplicate/null rejection. Optional
search fields must be omitted instead of sent as null. Both search and browse
reject an explicitly empty cursor; browse checks raw query presence so a binding
default cannot turn `?cursor=` into an absent value. Domain validation checks
pagination conflicts and the datasource independently validates the cursor
envelope, request fingerprint and ordering keys before querying records.

Vocabulary has its own raw-query validator using `url.ParseQuery`, since its
explicit empty `query` is meaningful. It rejects parse errors, invalid UTF-8,
unknown/repeated decoded names and invalid scalar bounds. Its literal generated
GET pattern requires both document read and search claims; ServeMux HEAD requests
inherit that same guard. Binding and operation validation run only afterward.
The datasource rechecks current authority before interpreting a vocabulary cursor.

Create validation deliberately preserves its existing sequence. A typed pointer decode
with unknown-field rejection checks field types and the required title, followed
by a raw UTF-8 check. Full-body unmarshalling then rejects trailing content and
a final null description. An exact field-name allowlist rejects case variants
that Go's typed decoder would otherwise accept. The validated bytes are restored
for generated decoding. Strict operation middleware would run too late for
these raw-body checks.

Repeated valid string fields keep their final value. An earlier invalid field
type still fails even when a later duplicate is a string. A null followed by a
valid string is accepted, while a final null is rejected. Business validation
runs before title trimming, preserving the existing length rules. Service-returned
validation errors retain their public mapping.

Validation now belongs to the matched operation. A URL containing an encoded
separator, such as `/api%2Fv1/documents`, does not match the generated route and
receives ServeMux's 404. The previous root URL comparison could reject its body
before routing. Canonical document URLs retain the same validation behavior.

## Architecture checks

Source checks recognize `presentation/<domain>` and nested packages as owned
by that domain. Root `httpapi` composes handlers and routes; shared
`httpapi/{contract,routing,transport}` cannot import feature presentation.
Models cannot import handlers/routes, and feature modules cannot import sibling
presentation, core service implementations or storage. Service ports may use
core value models; root injects implementations.

The [domain structure guide](domain-structure.md) describes the role-aware policy
and its limits. Tests retain nested middleware order/isolation, copied
configuration, wildcards, standard routing behavior, generated endpoints,
body/error compatibility, pagination, headers, deadlines and protected-route
checks. API and browser end-to-end suites exercise the running service against
real storage.

Job and reindex endpoints use the same generated router and document module.
Namespace pipeline/batch reads require either `documents:jobs:read` or
`documents:reindex`; namespace writes require reindex and job reads require the
job claim. System batch routes require system processing management. Raw reindex
bodies reject duplicate, unknown and null fields before decoding. Job and batch
list queries reject unknown, repeated and empty values. SQL independently rechecks
authority before resolving IDs or decoding cursor payloads.

Authority, disclosure and business decisions follow the
[service policy and atomic persistence guide](service-policy-and-persistence.md).
Keep scoped SQL, command preconditions, outboxes and execution fences in the
adapters while services select the use case and its policy.
