# Invoice extraction and storage

Invoices are a separate namespace-scoped domain. `invoices:read` protects list and
detail routes; owners and standard namespace roles receive it. Source documents
keep their own permissions. SQL rechecks the current session, credential revision
and membership in one repeatable-read transaction. Cross-library IDs disclose no
records.

## Extraction

New document workflows complete extraction, embedding and searchable publication
before a durable AI job runs invoice extraction and optional property extraction.
The AI job has its own queue, worker capacity, retries and status. Its invoice
stage is `invoicing`. Retained combined v1 histories preserve their original
activity order and version markers. The publication transaction queues follow-up
work without an uncoordinated database/Temporal dual write.

The isolated PDFium WASM processor enumerates embedded files and returns at most
one recognized invoice XML attachment. Compressed streams are supported.
Enumeration is limited to 32 attachments and XML to 2 MiB. Malformed recognized
attachments and multiple invoice attachments fail visibly instead of falling
back to AI. Original PDFs stay unchanged.

The invoice adapter reads CII used by ZUGFeRD/Factur-X, legacy ZUGFeRD 1, and UBL
Invoice/CreditNote. It checks root namespaces and rejects DTDs, external entities,
excessive nesting, oversized input, invalid amounts/currencies and invalid dates.
The stored profile is evidence supplied by XML. Extraction is not PDF/A, XSD,
Schematron or legal compliance certification: supported invoice XML embedded in
ordinary PDFs is also accepted.

Without structured XML, ordinary PDF and email text can use the
administrator-configured LLM when AI invoice extraction is enabled. Its switch
is independent of AI property extraction; the two steps share a model connection.
Each job uses its snapshotted switches, provider, model and credential reference.
Disabling either AI step still allows structured extraction.
The prompt treats text as untrusted data and distinguishes invoices from quotes
and emails merely forwarding attachments. Monetary output must be decimal
strings, with explicit currency. Missing fields remain empty. AI results carry
the model name and a review label. Provider errors and malformed output become
sanitized job failures.

New AI attempts first run a separate classifier with one constrained reason/type
field. Domain policy derives invoice, not_invoice or uncertain from that label,
so the model cannot return contradictory decision and reason values. Persisted
and public summaries still contain both decision and reason. Missing invoice fields
alone do not make a document negative. Only positive decisions run extraction;
negative and uncertain decisions skip extraction and continue to property work.
Uncertain outcomes remain visible as needing review and can be retried.

Classification uses at most 20,000 source characters distributed across four
samples spanning the start, middle and end. A sampled negative becomes uncertain;
non-positive sampled results get one wider pass of at most 50,000 source
characters. Each pass combines its samples into one request. A negative is
definitive only when all source text was supplied. Text with fewer than twenty
letters stays uncertain without inference. A negative conflicting with a prior invoice stays uncertain.
Neither outcome deletes an existing invoice. Positive-only extraction uses an
explicit schema containing only a required non-null `invoice` object; it has no
`isInvoice` field. Its shared field definitions require a nonempty invoice number
and seller name, uppercase three-letter currency syntax, and optional dates in ISO
format, empty or null. Unknown totals, buyer and other optional details can remain
absent or null; the adapter maps them to empty domain values. Actual
calendar dates, recognized currencies and source facts still require application
validation; schema-conforming JSON alone is insufficient. Failed grounding stays a
visible extraction failure rather than changing the classification.

Retained attempts use the earlier combined classifier/extractor. For these,
an explicit `isInvoice: false` result completes extraction without an invoice.
The adapter reads that decision before decoding invoice fields and ignores any
unused invoice object included with a negative decision. Positive decisions first
require a valid invoice; malformed JSON, missing decisions,
provider failures and invalid structured XML remain failures. The invoice adapter
then checks the same bounded OCR prefix supplied to inference. Both extraction
paths reject unsupported numeric facts with `invalid_invoice`, preserving the last
result. Missing values never turn a positive classification into a negative one.

Source validation searches for whole invoice, line and reference identifiers, every
populated monetary amount, quantity and rate, and complete issue/due/reference dates.
Values may appear anywhere in the supplied text. No invoice-label allowlist, seller
name check, currency-wording check or settlement-line classification is applied.
The model decides document purpose and the roles of parties and values. For example,
`Rechnungs-Nr. SYN-42` and `Rechnungsendbetrag in EUR 1.259,90` support the
identifier `SYN-42` and amount `1259.90` without recognizing either label.
Finding a value cannot prove that the model assigned it to the correct field.

Identifiers use escaped, case-insensitive regexes. Letters, digits and leading
zeros remain significant. Matching accepts OCR whitespace around hyphens, slashes,
periods and underscores, typographic hyphen variants, and gaps between letters and
digits. It preserves whole-identifier boundaries, including spaced suffixes, and
recognizes the abbreviated prefixes `Nr.` and `No.` without requiring an invoice
label. Regex metacharacters in identifiers are literal. Whitespace is not removed
between arbitrary digits or letters.

Numeric candidates use regexes followed by exact decimal-string comparison, never
floating point. Matching preserves signs and zero, supports leading signs,
accounting parentheses and attached trailing minus signs, and normalizes decimal comma/point
and valid three-digit grouping with punctuation, apostrophes, nonbreaking, narrow
nonbreaking or thin spaces. Horizontal whitespace around numeric punctuation is
accepted. Ordinary single-space grouping is accepted only when the grouped number
is the sole numeric expression on its physical line. Tabs, multiple column spaces,
line breaks and additional numeric cells prevent this grouping. Text alone cannot
distinguish an isolated grouped number from two cells with the same representation;
the extracted record still needs review. Grouped-number components cannot supply
separate numeric evidence. Numbers may touch either declared invoice currency code
or common quantity suffixes such as `kg`, `m`, `Stk` and `h`; arbitrary identifier
letters remain boundaries. Complete date spans cannot supply numeric evidence.
A single comma or point before three digits remains ambiguous: another unambiguous
number must establish a consistent decimal convention before that token is accepted.
Mixed conventions do not resolve such tokens. Non-ASCII digits and grouping schemes
other than three-digit groups are unsupported. AI output still uses canonical
decimal strings without grouping, whitespace or a leading plus.

Dates use regex captures followed by calendar validation. Numeric dates accept
whitespace around consistent dash, slash or period separators, including line
wraps. Year-first dates use year/month/day. English and German month names and
abbreviations support day-first and month-first forms with four-digit years.
Unambiguous numeric dates establish day/month order for other dates with the same
separator. Dotted dates default to day/month/year when no order is established;
conflicting evidence leaves ambiguous dates unsupported. Slash and year-last dash
dates have no default order. Two-digit years require a complete valid date elsewhere
in the supplied text establishing a unique matching full year. No century is
inferred from the current time. Unsupported or ambiguous optional values stay empty,
null or absent; zero is not a substitute for an unknown amount. The shared prompts
describe these conventions for both current and retained extraction paths.
Schema-derived type, unit, tax-category and payment-means codes are outside source
occurrence checks. No totals are calculated. Accepted records retain their AI
review label; these checks do not verify party roles or payment instructions.

The private inference schema distinguishes tax in the invoice currency
(`totalTax`) from optional VAT reported in another currency (`vatAccounting`,
either null or an object with a required currency/amount pair). The schema expresses
these as explicit alternatives. The adapter maps that pair to
the public `taxCurrency` and `taxAccountingAmount` fields. Single-currency
invoices leave it null. Net, tax and gross field descriptions include
English and German labels and distinguish totals excluding and including VAT.
Decimal patterns, closed child objects and nonempty
reference numbers constrain the model output. Validation still rejects missing
or invalid accounting currencies, amounts and other inconsistent data.

Rejected inference emits an `ai_invoice_validation` log with task, model and a
fixed reason category. Extraction categories distinguish an invalid envelope,
malformed payload, missing invoice, invalid accounting tax, invalid fields and
unsupported source evidence. Classifier categories
distinguish invalid JSON, invalid fields and unknown labels. These validation
logs contain no source text, extracted values or provider response bodies.
The shared Ollama adapter's INFO-level `ai_inference` log includes the complete
sent `prompt` (instructions, JSON schema and OCR text) and the original model
content in `response_json`, including content rejected by finish or invoice
validation. Credentials and thinking content are excluded. Public failure codes
remain `invalid_invoice` and `invalid_classification`.

Invoice extraction input is bounded to the first 100,000 Unicode characters.
The shared provider adapter preserves the selected invoice input. The
classification and extraction prompts require English JSON regardless of source
language. Classification and extraction both use the accepted invoice thinking
preference, independently of property extraction.
Both extraction paths share concise field instructions and the full field schema.
Names and addresses are preserved; identifier normalization is limited to the
formatting equivalents described above. Date examples show conversion to
zero-padded `YYYY-MM-DD` without a time; unsupported, invalid or ambiguous dates
remain empty. Missing values must not be invented or calculated.
Invoice classification, invoice extraction, property extraction and chat use
temperature 0.2 for both Ollama and external providers. The extraction
generation allowance is 50,000 tokens for both providers with thinking off.
Classification uses 256 tokens for its reason-only JSON response. Thinking defaults
off; enabling it adds 4,096 tokens to either shared reasoning/final-output budget.
Ollama receives `think: true/false`; external providers receive
`reasoning_effort: medium/none`. Native diagnostics record the accepted preference.
Provider/model support limits follow [property extraction](property-extraction.md).
Invoice extraction uses the configured context length from settings, capped at
the model's advertised maximum.
Its JSON generation responses have no separate application byte-size cap.
Model/provider limits and invoice field validation still apply. Classification,
property extraction and model metadata responses retain their 256 KiB cap.
Calls remain cancellable without a fixed HTTP deadline. Required invoice
identification and currency must be established. Large or unusual invoices may
need a later extraction implementation; original content remains in Documents.
Missing numeric evidence, including evidence beyond the input prefix, fails
extraction and preserves the prior invoice. Grounded positive evidence within the retained prefix remains usable.
Email PDF attachments enter the shared document pipeline independently.

## Persistence and concurrency

`invoices` stores one current record per namespace/document. Monetary columns use
PostgreSQL `numeric` without a fixed two-decimal scale. HTTP and Flutter use exact
decimal strings and explicit ISO currency codes; no money uses binary floating
point. Accounting VAT currency and amount are separate. Credit notes retain their
type and printed signs; analysis must interpret the type before calculating
balances.

XML decimal literals normalize optional plus signs and leading zeros without
rounding, retaining fractional scale. Numeric boolean charge indicators are
accepted alongside `true` and `false`. Normalized amounts support 24 integer and
12 fractional digits; the original XML preserves the supplied representation.

Typed header columns retain parties and identifiers, addresses, dates and payment
details. Ordered `invoice_lines`, `invoice_taxes`, `invoice_allowances`,
`invoice_references` and `invoice_notes` tables retain quantities, unit prices,
tax breakdowns, charges, references and notes. Composite foreign keys enforce
namespace ownership and cascade deletion. Raw structured XML remains as source
evidence. The source document is the inspection and download link. See the
[relational storage decision](persistence.md); invoice operations do not use JSONB.

The invoice source locks the document before the processing generation. Claim and
publication both check OCR revision, active generation and deadline. No database
transaction spans a PDF or LLM operation. Header upsert, child replacement,
lexical search projection, generation checkpoint and next-stage transition commit
together. Replays do not duplicate invoices.
Retained combined decisions can remove prior AI records; new classifier decisions
preserve them. Failed attempts retain the last successful record.

Migration 035 stamps retained AI attempts with classifier version zero and defaults
new attempts to version one. Typed columns on document_ai_jobs store decision,
reason, pass, source size and supplied source size. Each pass commits before the
next provider call. Checkpoint writes recheck the active attempt, OCR revision,
stage and previous pass under the existing document/job locks. Activity recovery
reuses the saved classification; workflow names, payloads and command order stay
unchanged. Current processing and paginated history expose the summary through
the existing document/jobs permissions. Both persistence paths preserve structured
records from AI deletion or replacement inside the existing transaction. A later property failure also keeps the saved invoice while the independent AI
pipeline reports its failed step. New invoice processing starts only after
embeddings and searchable publication have succeeded. Retained combined v1 jobs
keep their historical stage behavior.
Deleting a source cascades. Changes publish
the existing documents invalidation topic for authorized UI refresh.

Corrections retain external invoice number/date. Detail lookup resolves a link
only when exactly one invoice in the namespace matches that number, any specified
date, and seller tax ID (or registration ID when no tax ID exists). Ambiguous or
missing predecessors remain textual references. Importing a predecessor later
resolves links without rewriting older invoices.

Lists use bounded keyset pages. Without an explicit sort, browsing orders by
stable creation time and UUID and search orders by relevance, creation time and
UUID. Explicit ascending or descending order supports creation, issue and due
dates and case-insensitive alphanumeric invoice numbers, suppliers and buyers.
Missing dates and empty text sort last in both directions; creation time and UUID
break ties. Search
accepts `q` of up to 200 Unicode characters and matches only invoice properties:
numbers, parties, dates, currencies, line items, tax/allowance details, payment,
references and notes. Original document titles and OCR are excluded. Exact invoice
numbers rank first, followed by literal number/party matches, full-text matches
and typo-tolerant matches. Quoted phrases, OR and excluded words use the Documents
full-text syntax and disable fuzzy fallback so operators keep their meaning.

Exact filters select invoice number, supplier name, buyer name, currency, type
code, format and payment method code. Source, full-text search and all property
filters combine with AND. Inclusive issue/due/creation date bounds accept ISO
calendar dates; creation bounds use UTC days. Gross-total bounds compare exact
decimals and require a currency, so different currencies are never mixed.

The `filter-values` endpoint uses the same `invoices:read` claim and supplies
distinct nonempty values across the current library. Each request searches the
whole vocabulary using literal, case-insensitive text and returns at most 50
values with a deterministic keyset continuation. Values remain available
independently of current invoice filters. All seven value fields use this
endpoint; the UI never builds vocabularies from a loaded invoice page.

Invoice cursors bind the namespace, all filters, trimmed query and sort. Value
cursors bind the namespace, field and trimmed query. Invoice cursors allow up to
32 KiB to accommodate the model's 4,000-character text fields without truncation;
other pagination endpoints retain their existing bounds. Unfiltered default
browse/search cursors remain compatible.
The bundled nginx server accepts request lines up to 512 KiB so percent-encoded
Unicode filter values and their cursor remain usable together. Deployments with
another reverse proxy need the same request-line allowance for maximum-length
invoice values.
Search has a five-second SQL deadline. Only the bounded selected page's header and
child values are hydrated. Responses use one authorized repeatable-read snapshot;
there is no snapshot guarantee across pages.

## Verification

Unit tests cover CII/legacy/UBL mapping, decimals, hostile XML, compressed PDF
attachments, AI validation and Temporal versioning. Disposable-schema integration
tests cover checkpoints, stale OCR, exact numeric storage, correction links,
cursors, revoked access and deletion. Filter coverage includes multi-page sorting,
missing dates, exact decimal bounds, long values, literal vocabulary search and
cross-library isolation. Compiled API E2E exercises PDF/email
processing, restart and isolation. See the
[testing guide](../../development/testing.md) for suite commands and prerequisites.
Storage tests also cover complete typed
round trips, ordered children, cascade deletion, failed-write rollback, search
projection replacement, invoice-only queries and criteria-bound cursors.

## Follow-up ownership

New invoice processing runs after searchable document publication in the independent
`domabas.DocumentAI.v1` workflow. Structured CII/UBL extraction remains automatic
with both inference switches disabled. Malformed or excessive embedded invoice
attachments produce typed downstream diagnostics without blocking OCR or embedding.
Invoice writes verify the latest AI attempt, ready ingestion generation and OCR
revision. Failure changes only AI status. Disabled/skipped inference retains any
existing invoice, while a completed negative classification can remove only an AI
record. Structured records retain priority over subsequent AI extraction.
See [document ingestion](document-ingestion.md) for durable admission and retry.

Authority, disclosure and business decisions follow the
[service policy and atomic persistence guide](service-policy-and-persistence.md).
Keep scoped SQL, command preconditions, outboxes and execution fences in the
adapters while services select the use case and its policy.
