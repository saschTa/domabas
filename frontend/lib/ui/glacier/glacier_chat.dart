import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_job_progress.dart';
import '../app_presenters.dart';
import 'glacier_controls.dart';
import 'glacier_surfaces.dart';
import 'glacier_workspace_geometry.dart';
import 'glacier_theme.dart';

@immutable
class GlacierConversation {
  const GlacierConversation({
    required this.id,
    required this.title,
    required this.updated,
  });
  final String id, title, updated;
}

class GlacierConversationHistory extends StatelessWidget {
  const GlacierConversationHistory({
    super.key,
    required this.conversations,
    required this.selectedId,
    required this.onSelect,
    required this.onNew,
    this.onDelete,
    this.onMore,
    this.notice,
    this.busy = false,
    this.showNew = true,
  });
  final List<GlacierConversation> conversations;
  final String? selectedId;
  final ValueChanged<String>? onSelect, onDelete;
  final VoidCallback? onNew, onMore;
  final Widget? notice;
  final bool busy, showNew;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showNew)
        Padding(
          padding: const EdgeInsets.all(16),
          child: GlacierButton(
            label: 'New conversation',
            icon: Icons.add,
            onPressed: busy ? null : onNew,
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
        child: Text(
          'Your conversations',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      if (notice != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: notice!,
        ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            if (conversations.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Your conversations will appear here.'),
              ),
            for (final conversation in conversations)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: conversation.id == selectedId
                      ? GlacierTokens.of(context).glass
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: conversation.id == selectedId
                          ? GlacierTokens.of(context).edge
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: busy || onSelect == null
                              ? null
                              : () => onSelect!(conversation.id),
                          borderRadius: BorderRadius.circular(12),
                          child: Semantics(
                            selected: conversation.id == selectedId,
                            button: true,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    conversation.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    conversation.updated,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (onDelete != null)
                        GlacierIconButton(
                          label: 'Delete ${conversation.title}',
                          icon: Icons.delete_outline,
                          onPressed: busy
                              ? null
                              : () => onDelete!(conversation.id),
                        ),
                    ],
                  ),
                ),
              ),
            if (onMore != null)
              GlacierButton(
                label: 'Load older conversations',
                onPressed: busy ? null : onMore,
              ),
          ],
        ),
      ),
    ],
  );
}

@immutable
class GlacierChatSource {
  const GlacierChatSource({
    required this.title,
    required this.onOpen,
    this.excerpt,
    this.key,
  });
  final String title;
  final Key? key;
  final String? excerpt;
  final VoidCallback? onOpen;
}

class GlacierChatMessage extends StatelessWidget {
  const GlacierChatMessage({
    super.key,
    required this.text,
    this.fromUser = false,
    this.status,
    this.statusDescription,
    this.active = false,
    this.failed = false,
    this.sources = const [],
    this.onSendAgain,
    this.textKey,
    this.retryKey,
    this.showRetry = false,
    this.statusTone,
  });
  final String text;
  final String? status, statusDescription;
  final bool fromUser, active, failed;
  final List<GlacierChatSource> sources;
  final VoidCallback? onSendAgain;
  final Key? textKey, retryKey;
  final bool showRetry;
  final AppTone? statusTone;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: (constraints.maxWidth * (fromUser ? .8 : 1))
            .clamp(0, 740)
            .toDouble(),
        child: _ChatMessageSurface(
          fromUser: fromUser,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fromUser ? 'You' : 'Domabas',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 12,
                  color: GlacierTokens.of(context).muted,
                ),
              ),
              if (text.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(
                  text,
                  key: textKey,
                  style: const TextStyle(fontSize: 14, height: 1.75),
                ),
              ],
              if (status != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (active) AppJobSpinner(label: status!),
                      AppStatusBadge(
                        label: status!,
                        tone:
                            statusTone ??
                            (failed ? AppTone.danger : AppTone.info),
                      ),
                    ],
                  ),
                ),
                if (statusDescription != null) ...[
                  const SizedBox(height: 8),
                  Text(statusDescription!),
                ],
              ],
              if (sources.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Documents consulted',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final source in sources)
                      Tooltip(
                        message: source.excerpt ?? source.title,
                        child: GlacierButton(
                          key: source.key,
                          label: source.title,
                          icon: Icons.description_outlined,
                          onPressed: source.onOpen,
                        ),
                      ),
                  ],
                ),
              ],
              if (showRetry || onSendAgain != null) ...[
                const SizedBox(height: 12),
                GlacierButton(
                  key: retryKey,
                  label: 'Send again',
                  icon: Icons.replay,
                  onPressed: onSendAgain,
                  kind: GlacierButtonKind.quiet,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _ChatMessageSurface extends StatelessWidget {
  const _ChatMessageSurface({required this.fromUser, required this.child});
  final bool fromUser;
  final Widget child;
  @override
  Widget build(BuildContext context) => fromUser
      ? GlacierSurface(
          radius: 13,
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 15),
          child: child,
        )
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: child,
        );
}

class GlacierChatComposer extends StatelessWidget {
  const GlacierChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.onStop,
    this.onCheck,
    this.enabled = true,
    this.busy = false,
    this.stopPending = false,
    this.notice,
    this.focusNode,
    this.onChanged,
    this.errorText,
    this.inputKey,
    this.sendKey,
    this.stopKey,
    this.checkKey,
    this.minLines = 3,
    this.sendLabel = 'Send',
  });
  final TextEditingController controller;
  final VoidCallback? onSend, onStop, onCheck;
  final bool enabled, busy, stopPending;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final Key? inputKey, sendKey, stopKey, checkKey;
  final int minLines;
  final String sendLabel;
  final Widget? notice;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) {
      final canSend =
          enabled &&
          !busy &&
          onCheck == null &&
          !(value.composing.isValid && !value.composing.isCollapsed) &&
          value.text.trim().isNotEmpty &&
          onSend != null;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
            if (canSend) onSend!();
          },
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
            if (canSend) onSend!();
          },
        },
        child: GlacierSurface(
          surface: true,
          radius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notice != null) ...[notice!, const SizedBox(height: 12)],
              TextField(
                key: inputKey,
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                enabled: enabled && !stopPending,
                minLines: minLines,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  errorText: errorText,
                  errorMaxLines: 3,
                  hintText: 'Ask about your documents…',
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
              const SizedBox(height: 12),
              GlacierWorkspaceGeometry.measureEndActions(
                context,
                followingExtent: 34,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Ctrl / ⌘ + Enter to send · Enter for a new line',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (onCheck != null)
                      GlacierButton(
                        key: checkKey,
                        label: 'Check sent message',
                        onPressed: onCheck,
                        kind: GlacierButtonKind.primary,
                      )
                    else if (busy)
                      GlacierButton(
                        key: stopKey,
                        label: stopPending ? 'Stop requested' : 'Stop reply',
                        icon: Icons.stop,
                        onPressed: stopPending ? null : onStop,
                      )
                    else
                      GlacierButton(
                        key: sendKey,
                        label: sendLabel,
                        icon: Icons.arrow_upward,
                        onPressed: canSend ? onSend : null,
                        kind: GlacierButtonKind.primary,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class GlacierChatScreen extends StatelessWidget {
  const GlacierChatScreen({
    super.key,
    required this.history,
    required this.messages,
    required this.composer,
    this.notice,
    this.onEarlier,
    this.onLatest,
    this.scrollController,
    this.title = 'New conversation',
    this.actions = const [],
  });
  final Widget history, composer;
  final List<Widget> messages;
  final Widget? notice;
  final VoidCallback? onEarlier, onLatest;
  final ScrollController? scrollController;
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow =
          constraints.maxWidth < 760 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      final shareComposerHeight =
          constraints.maxHeight < 600 &&
          MediaQuery.textScalerOf(context).scale(14) > 20;
      final boundedComposer = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: constraints.maxHeight * .48),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: composer,
        ),
      );
      final transcript = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              spacing: 12,
              children: [
                if (narrow)
                  GlacierButton(
                    label: 'History',
                    icon: Icons.history,
                    onPressed: () => showGlacierDialog<void>(
                      context: context,
                      builder: (dialogContext) => Dialog(
                        backgroundColor: Colors.transparent,
                        child: GlacierSurface(
                          padding: EdgeInsets.zero,
                          child: SizedBox(
                            width: 360,
                            height: MediaQuery.sizeOf(context).height * .8,
                            child: Column(
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: GlacierIconButton(
                                    label: 'Close history',
                                    icon: Icons.close,
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(),
                                  ),
                                ),
                                Expanded(child: history),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontSize: 19),
                ),
                ...actions,
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                if (notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 26),
                    child: notice!,
                  ),
                if (onEarlier != null)
                  Align(
                    alignment: Alignment.center,
                    child: GlacierButton(
                      label: 'Load earlier messages',
                      onPressed: onEarlier,
                      kind: GlacierButtonKind.quiet,
                    ),
                  ),
                if (messages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What would you like to find?',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Ask a question about your private library. Documents used in a reply will appear alongside it.',
                        ),
                      ],
                    ),
                  ),
                for (final message in messages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: message,
                  ),
              ],
            ),
          ),
          if (onLatest != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GlacierButton(
                  label: 'Jump to latest',
                  onPressed: onLatest,
                  kind: GlacierButtonKind.quiet,
                ),
              ),
            ),
          if (shareComposerHeight)
            Flexible(child: boundedComposer)
          else
            boundedComposer,
        ],
      );
      final content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!narrow)
            Container(
              width: 240,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: GlacierTokens.of(context).border),
                ),
              ),
              padding: const EdgeInsets.only(right: 10),
              child: history,
            ),
          Expanded(child: transcript),
        ],
      );
      final geometry = GlacierWorkspaceGeometry.maybeOf(context);
      return geometry == null
          ? content
          : SingleChildScrollView(
              primary: false,
              child: Column(
                children: [
                  SizedBox(height: constraints.maxHeight, child: content),
                  SizedBox(height: geometry.trailingExtent),
                ],
              ),
            );
    },
  );
}
