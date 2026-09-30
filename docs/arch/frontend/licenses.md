# Third-party license reader

The sign-in screen, session recovery and native first-run server setup include a
small Licenses button at the bottom right. It opens the same offline reader with
a Back action, without requiring a server connection or account. The footer
occupies its own layout space inside safe insets and stays above the keyboard;
the form scrolls independently. Returning preserves the form's draft.

User settings also contains a Licenses navigation entry for every authenticated
workspace role. It remains a secondary destination in the mobile More/settings
chooser. This is public bundled attribution, so it adds no scoped claim, API
endpoint or access to library data.

`ThirdPartyLicense` and `ThirdPartyLicenseNotice` are immutable domain values.
`ThirdPartyLicenseRepository` supplies them. The app composition root injects a
`BundledThirdPartyLicenseRepository`, whose asset data source reads the generated
`assets/licenses/third-party.json` and Flutter's `LicenseRegistry`. A dedicated
mapper expands shared notice text IDs into domain values. The repository merges
runtime notices by package, preserving additional notices and removing exact
whitespace-equivalent duplicates. No API request or backend is needed. The web
app must first load the page and bundled assets before reading notices offline.

The workspace owns and closes `LicensesCubit`; it loads only on first navigation.
The public reader's app-composed route owns its separate repository and Cubit,
loads on opening and closes the Cubit when the route is removed. A session or
server replacement removes the public route with its owning navigator.
Search matches every entered word across name, version, component and license
label. The shared `AppPagedList` bounds local pages to 20 results and keeps all
entries reachable. Changing the search resets pagination. A responsive `AppDialog`
shows selectable full notices and source addresses with a fixed Close action.
Read/decode failures expose a retry state and disposal ignores late completions.

The existing PDF viewer's Flutter license page and registrations for Lora,
PDFium and OpenCV are retained. The new reader also includes backend, tooling,
models and infrastructure evidence that Flutter cannot collect automatically.

The canonical retained catalog and supplement manifest live under
`third_party/licenses/`. Bun generation produces the app asset and a Markdown
index, deduplicating identical text by SHA-256 while preserving copyright text.
Normal generation/checks are offline and do not need dependency caches. Evidence
collection is an explicit maintainer step; missing grants remain visible entries.
See [inventory workflow](../../../third_party/README.md#complete-inventory-and-app-screen)
and [commercial review](../../../third_party/COMMERCIAL_LICENSE_REVIEW.md) for
scope, evidence gaps and source-distribution obligations.

Repository tests cover bundled loading, runtime merging, immutability and invalid
assets. Widget tests cover search, paging/reset, notices, retries, lifecycle,
small screens, enlarged text and all-role navigation. Tooling validation checks
locked package coverage, text integrity and stale generated artifacts.
