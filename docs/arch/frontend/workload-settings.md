# Workload settings

Admin settings includes Workload limits for users with `system:workloads:manage`.
The screen reads the shared scheduler API through a domain repository and Cubit.
It shows each resource's editable active-job limit, supported maximum and current
reserved usage. The active view fetches a baseline, then refreshes on authorized workload WebSocket hints. Ready and resync repair gaps after reconnect. During a disconnect, manual refresh remains available. Select a pipeline to see the slots it holds on each resource alongside the total in use across the installation. A wide view connects the selected pipeline on the left to the resources on the right. Phone widths and large text use a vertical layout.

Worker capacity is measured in admitted background jobs. Ollama explains the
half-queue ceiling and external providers use safe origin labels. Starting and
draining jobs remain counted. Saving a smaller limit lets running jobs finish;
new work waits. Unsaved edits are preserved through validation or save failures,
and stale revisions require a reload before another save.

Pull down at the top of the form to refresh saved values and usage while
preserving each edited field,
including an empty or newly out-of-range draft. Save remains disabled until all
limits are positive whole numbers within the current server-provided bounds.
Conflicts and uncertain writes require an explicit refresh; reset restores the
saved limits. A successful save clears the draft. The scoped repository cancels
requests when its authenticated session ends, and late reads cannot update a
closed Cubit.

Successful saves use a brief accessible SnackBar outside the scrolling form.
Resource fields keep their controllers when the saved response arrives, and
capacity guidance keeps the same layout when a lower limit starts draining jobs.
Saved limits and active counts use separate labeled cells so changing the number
of digits does not reflow a shared status line and move later controls.
Saving does not insert a banner above the controls or reset the scroll position.

Resource IDs remain strings, so the UI accepts additional provider identities
without a client release. Immutable domain values contain the mapped resources
and pipeline requirements; generated API models remain in data adapters. The
screen uses the server's safe resource labels and verifies that every pipeline
resource reference is present before displaying the response. It does not infer
a specific job's blocked resource or its queue position from these requirements.
The diagram shows configured resources and any other provider still serving an active request for the selected pipeline. A missing attribution field from an older backend is displayed as unavailable. Capacity changes animate unless the device requests reduced motion.

Workload administrators edit Paperless download capacity here. Users who can
manage Paperless retrievals but lack workload access see a dedicated editor instead.
External addresses in the flow and limit fields carry an “external API provider” label.
Paperless and email retrieval reserve worker capacity; accepted originals enter
the separate ingestion pipeline. Document AI and chat use the selected provider
resource. Pipeline screens no longer describe ingestion preemption or show the
former independent concurrency values as effective limits.

The underlying policy and retention semantics are documented in the
[backend scheduler](../backend/resource-scheduler.md).
