# Invoice workspace

Admin document processing shows separate AI invoice and AI property switches,
with a clearly labelled shared model connection. Pipeline cards and historical
job views show each step's own saved enable state and model. The invoice card
also explains that embedded e-invoice XML remains available when invoice AI is
off. Each card opens the same settings editor without coupling the switches.

Invoices is a primary workspace destination for users with `invoices:read` in
the selected library. The app composition root constructs the invoice repository,
owns the collection Cubit, and passes permitted document-opening callbacks into
the feature. The invoice feature never imports document presentation code.

The `invoice` domain contains immutable invoice values and a small read repository
interface. The data source owns generated HTTP calls, timeouts and cancellation.
The repository checks page continuations, record identity and exact decimal
strings before mapping generated models into domain values. Session retirement
cancels invoice requests with the other authenticated resources.

## Collection and detail

The collection uses shared themed page, surface, record, status and pagination
presenters. Each row identifies the supplier, invoice number, gross total with
currency, dates and extraction source. Credit notes and corrected invoices use
explicit labels. The source chooser offers All invoices, E-invoices and AI
extracted. No amount is converted to a floating-point number or combined with
other currencies. Missing values remain visibly missing.
Pulling down from the top refreshes the collection, including an empty list.
Refresh waits for the current read, retains the loaded row window and visible
page, and preserves search and filter values. Errors keep a visible retry action.

Search follows Documents: a persistent field, 300-millisecond debounce, immediate
Search or Enter, and an explicit clear action. It searches extracted invoice
properties, including number, parties, line items, payment details, references and
notes; original document title and OCR are outside its scope. Source and query
combine. Clear removes the text while retaining the chosen source. The field caps
valid queries at 200 Unicode characters and waits for IME composition to finish.
The feature-owned toolbar uses the shared search field and collection controls.
App composition places it in the top bar, with library selection on the right.
Source selection, filters and sort remain available while invoices
scroll inside the fixed full-height content pane. Compact widths use a second controls row; controller
and query state survive layout changes.

Sort offers newest or oldest added, earliest or latest due date and issue date,
and ascending or descending invoice number, supplier and customer. Automatic uses
relevance for a nonempty search and newest added otherwise. Explicit sort survives
search edits, source changes and property-filter updates. The server sorts the
complete matching collection, placing missing dates and text values last.

Filters opens a draft form for exact invoice number, supplier, customer, currency,
invoice type, format and payment method, together with added, issue and due date
ranges and a gross-total range. Date endpoints are inclusive; added dates use UTC
days. Total ranges require a selected currency and use exact decimal strings,
including negative credit notes. The form validates real calendar dates, ordered
ranges and the server's 24-integer/12-fractional-digit decimal bounds without
floating-point conversion. Apply commits the draft; Cancel and dismissal discard
it. Active summaries remove individual properties or ranges. Clear filters keeps
search, source and sort; removing the currency summary also removes its total range.

Every property chooser searches the current library through the invoice filter-value
endpoint, independently of the current invoice criteria. No options come from loaded
invoice rows or a hardcoded code list. Friendly labels explain known invoice types,
formats and common payment methods while retaining unknown codes. Each chooser
retains one page of 20 values and up to 50 prior cursor positions. Next continues
through the complete vocabulary; Previous and First support returning to older
positions. Search resets to the first page and uses the same 300-millisecond
debounce, immediate keyboard submission and IME guard as invoice search. It cancels
and fences prior requests. Failed page reads retain the current page and Retry
reissues the failed continuation. Closing the chooser cancels its request.

The draft form and value chooser share one owned dialog route. Switching the screen
owner or disposing it removes that route, and stale callbacks cannot apply changes.
The bounded dialog scrolls fields, option rows and pagination while keeping the
current close/apply actions reachable. Controls wrap at narrow widths and enlarged
text. Long values retain their complete tooltip and selection value.

The list reads 20 records at a time and exposes Previous and Next controls.
Its loaded invoice count appears below the rows beside pagination, including when
only one page is loaded. The count describes loaded records, not a server-wide
total. Empty successful results show zero below the empty state. Active loading,
search and error feedback sits in a bounded row above phone navigation; healthy
collections reserve no blank status area above the rows.
Automatic refresh rereads the loaded row window from the head, using at most one
bounded request per previously loaded page and the new responses' continuations.
It publishes the refreshed rows and cursor together, updating changed invoices,
removing deleted or nonmatching invoices, and including new head entries. The
visible page is retained; invoices pushed beyond the loaded window remain
reachable through Next. Concurrent ordering changes across requests retain the
usual keyset pagination limits. Failed reads preserve
the last successful snapshot and offer a retry. The Cubit pauses while the
destination is hidden or the app is backgrounded, polls every 15 seconds while
visible, and responds to the existing document/processing invalidations. An edit
cancels and fences the previous read immediately. Desired controls remain separate
from the committed snapshot, so typing and source changes retain rows, cursor and
the local visible page until a current request succeeds. Pending and failed updates
identify previous results. Continuation is disabled while controls differ from the
snapshot; a successful criteria change starts from the first page. Background
refresh waits during debounce, composition and invalid input.

Details use the shared bounded scrolling dialog. Each dialog owns an independent
detail Cubit and cancels its read on dismissal. It shows parties, dates, amounts,
line items, tax breakdown, allowances, payment data, references, notes and source
provenance. Embedded collections show at most 20 entries per visible page.
Resolved references open another invoice dialog; unresolved references remain
readable. Opening an original closes the invoice dialog and delegates to app
composition. That action additionally requires `documents:read`.

Structured source means data extracted from embedded XML, without implying a
compliance certification. AI results use a written review label and a warning
tone. Colors come from the current theme; labels convey meaning independently of
color. Rows and detail fields stack with narrow widths or enlarged text. Material
buttons retain keyboard interaction and natural text scaling.

The document pipeline includes invoice extraction between OCR and property
extraction. The current invoicing stage is shown explicitly. Historical jobs do
not have public invoice checkpoint evidence, so their invoice stage says Not
recorded rather than inferring a successful check from a later stage.

See [backend invoice extraction and storage](../backend/invoices.md) for source
evidence and query behavior, and [shared UI components](components.md) for the
common search and detail presentation.
