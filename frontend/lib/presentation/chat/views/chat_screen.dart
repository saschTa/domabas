import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/chat/models/chat.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/chat_cubit.dart';
import '../widgets/chat_message_card.dart';

final class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.cubit,
    required this.libraryName,
    this.onOpenDocument,
  });
  final ChatCubit cubit;
  final String libraryName;
  final Future<void> Function(String)? onOpenDocument;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

final class _ChatScreenState extends State<ChatScreen> {
  late final _composer = TextEditingController(text: widget.cubit.state.draft);
  ScrollController? _scroll;
  final _messageKeys = <String, GlobalKey>{};
  final _focus = FocusNode();
  bool _away = false;
  int _latestGeneration = 0;
  int _earlierGeneration = 0;
  String? _earlierConversationId;
  bool get _loadingEarlier =>
      _earlierConversationId != null &&
      cubit.state.selected?.id == _earlierConversationId;
  ChatCubit get cubit => widget.cubit;
  void _bindScroll(BuildContext context) {
    final scroll = PrimaryScrollController.of(context);
    if (identical(_scroll, scroll)) return;
    _scroll?.removeListener(_scrollChanged);
    _scroll = scroll;
    scroll.addListener(_scrollChanged);
  }

  void _scrollChanged() {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients) return;
    final away = scroll.position.extentAfter > 120;
    if (away != _away && mounted) setState(() => _away = away);
  }

  void _latest() {
    final generation = ++_latestGeneration;
    final scroll = _scroll;
    var remainingFrames = 8;
    void follow(Duration _) {
      if (mounted &&
          generation == _latestGeneration &&
          identical(_scroll, scroll) &&
          scroll != null &&
          scroll.hasClients &&
          scroll.position.extentAfter > 0 &&
          remainingFrames-- > 0) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
        if (remainingFrames > 0) {
          WidgetsBinding.instance.addPostFrameCallback(follow);
          WidgetsBinding.instance.scheduleFrame();
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(follow);
  }

  Future<void> _send() async {
    await cubit.send();
    if (mounted) {
      _latest();
      _focus.requestFocus();
    }
  }

  Future<void> _earlier() async {
    final scrollGeneration = ++_latestGeneration;
    final earlierGeneration = ++_earlierGeneration;
    final conversationId = cubit.state.selected?.id;
    _earlierConversationId = conversationId;
    final scroll = _scroll;
    final anchor = _messageKeys[cubit.state.messages.firstOrNull?.id];
    final anchorOffset = _messageOffset(anchor);
    final previousExtent = scroll != null && scroll.hasClients
        ? scroll.position.maxScrollExtent
        : 0.0;
    final previousOffset = scroll != null && scroll.hasClients
        ? scroll.offset
        : 0.0;
    await cubit.earlierMessages();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          scrollGeneration == _latestGeneration &&
          cubit.state.selected?.id == conversationId &&
          identical(_scroll, scroll) &&
          scroll != null &&
          scroll.hasClients) {
        final currentAnchorOffset = _messageOffset(anchor);
        final offset = anchorOffset != null && currentAnchorOffset != null
            ? scroll.offset + currentAnchorOffset - anchorOffset
            : previousOffset + scroll.position.maxScrollExtent - previousExtent;
        scroll.jumpTo(offset.clamp(0.0, scroll.position.maxScrollExtent));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              scrollGeneration == _latestGeneration &&
              cubit.state.selected?.id == conversationId &&
              identical(_scroll, scroll) &&
              scroll.hasClients) {
            final currentAnchorOffset = _messageOffset(anchor);
            if (anchorOffset != null && currentAnchorOffset != null) {
              scroll.jumpTo(
                (scroll.offset + currentAnchorOffset - anchorOffset).clamp(
                  0.0,
                  scroll.position.maxScrollExtent,
                ),
              );
            }
          }
          if (earlierGeneration == _earlierGeneration) {
            _earlierConversationId = null;
          }
        });
        WidgetsBinding.instance.scheduleFrame();
      } else {
        if (earlierGeneration == _earlierGeneration) {
          _earlierConversationId = null;
        }
      }
    });
  }

  double? _messageOffset(GlobalKey? key) {
    final render = key?.currentContext?.findRenderObject();
    return render is RenderBox && render.attached && render.hasSize
        ? render.localToGlobal(Offset.zero).dy
        : null;
  }

  Future<void> _history() => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  const Expanded(child: Text('Your conversations')),
                  IconButton(
                    tooltip: 'Close history',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<ChatCubit, ChatState>(
                bloc: cubit,
                builder: (context, state) => _ChatHistory(
                  cubit: cubit,
                  state: state,
                  onSelected: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    _composer.dispose();
    _scroll?.removeListener(_scrollChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<ChatCubit, ChatState>(
    bloc: cubit,
    listener: (context, state) {
      if (_composer.text != state.draft) {
        _composer.value = TextEditingValue(
          text: state.draft,
          selection: TextSelection.collapsed(offset: state.draft.length),
        );
      }
      if (!_away && !_loadingEarlier && !state.loadingMessages) _latest();
    },
    builder: (context, state) => LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return _compactPage(context, state, constraints);
        }
        return AppPage(
          title: 'AI chat',
          surface: false,
          insetBody: false,
          description:
              'Ask questions about your documents in ${widget.libraryName}.',
          actions: [
            IconButton(
              key: const Key('chatHistory'),
              tooltip: 'Conversation history',
              onPressed: state.canManageConversations ? _history : null,
              icon: const Icon(Icons.history),
            ),
            OutlinedButton.icon(
              key: const Key('newChat'),
              onPressed: state.canManageConversations
                  ? cubit.newConversation
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('New chat'),
            ),
          ],
          child: LayoutBuilder(
            builder: (context, constraints) {
              _bindScroll(context);
              final wide =
                  constraints.maxWidth >= 850 &&
                  MediaQuery.textScalerOf(context).scale(14) < 23;
              final transcript = _transcript(
                context,
                state,
                constraints.maxHeight,
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide) ...[
                    SizedBox(
                      width: 260,
                      child: AppSurface(
                        padding: const EdgeInsets.all(12),
                        child: _ChatHistory(cubit: cubit, state: state),
                      ),
                    ),
                    const SizedBox(width: 20),
                  ],
                  Expanded(child: transcript),
                ],
              );
            },
          ),
        );
      },
    ),
  );

  Widget _compactPage(
    BuildContext context,
    ChatState state,
    BoxConstraints constraints,
  ) => AppPage(
    title: 'AI chat',
    surface: false,
    insetBody: false,
    actions: [
      IconButton(
        key: const Key('chatHistory'),
        tooltip: 'Conversation history',
        onPressed: state.canManageConversations ? _history : null,
        icon: const Icon(Icons.history),
      ),
      IconButton(
        key: const Key('newChat'),
        tooltip: 'New chat',
        onPressed: state.canManageConversations ? cubit.newConversation : null,
        icon: const Icon(Icons.add),
      ),
    ],
    child: LayoutBuilder(
      builder: (context, bounds) {
        _bindScroll(context);
        return _transcript(context, state, bounds.maxHeight, compact: true);
      },
    ),
  );

  Widget _transcript(
    BuildContext context,
    ChatState state,
    double height, {
    bool compact = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final messageIds = state.messages.map((message) => message.id).toSet();
    _messageKeys.removeWhere((id, key) => !messageIds.contains(id));
    height = (height - MediaQuery.paddingOf(context).bottom).clamp(0, height);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: AppSurface(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            AppProgressSlot(
              active: state.loading || state.loadingMessages || state.sending,
            ),
            Expanded(
              child: AppRefreshable(
                onRefresh:
                    state.loading ||
                        state.loadingHistory ||
                        state.loadingMessages ||
                        state.sending ||
                        state.stopping ||
                        state.deletingConversationId != null
                    ? null
                    : cubit.load,
                child: NotificationListener<UserScrollNotification>(
                  onNotification: (notification) {
                    if (notification.direction != ScrollDirection.idle) {
                      _latestGeneration++;
                    }
                    return false;
                  },
                  child: ListView(
                    controller: _scroll,
                    key: const Key('chatTranscript'),
                    padding: EdgeInsets.all(compact ? 12 : 20),
                    children: [
                      if (!compact)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_outlined,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      state.selected?.title.isNotEmpty == true
                                          ? state.selected!.title
                                          : 'Ask your library',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    if (state.configuration != null)
                                      Text(
                                        '${state.configuration!.provider == 'ollama' ? 'Internal Ollama' : 'External service'} · ${state.configuration!.model}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (state.configuration?.enabled == false)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: AppNotice(
                            tone: AppTone.info,
                            title: 'Chat is paused',
                            message: 'An administrator has paused new chat messages. Your conversations remain available.',
                          ),
                        ),
                      if (state.error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: AppNotice(
                            message: state.error!,
                            action: state.uncertain
                                ? TextButton(
                                    key: const Key('reconcileChatMessage'),
                                    onPressed: state.sending
                                        ? null
                                        : () => cubit.send(reconcile: true),
                                    child: const Text('Check sent message'),
                                  )
                                : TextButton(
                                    onPressed: state.loading
                                        ? null
                                        : cubit.load,
                                    child: const Text('Retry'),
                                  ),
                          ),
                        ),
                      if (state.updatesError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: AppNotice(
                            tone: AppTone.warning,
                            message: state.updatesError!,
                          ),
                        ),
                      if (state.messageCursor != null)
                        Center(
                          child: TextButton.icon(
                            key: const Key('earlierChatMessages'),
                            onPressed:
                                state.loadingMessages ||
                                    state.deletingConversationId != null
                                ? null
                                : _earlier,
                            icon: const Icon(Icons.expand_less),
                            label: const Text('Load earlier messages'),
                          ),
                        ),
                      if (state.messages.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 48,
                                color: scheme.primary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                state.loadingMessages
                                    ? 'Loading your conversation…'
                                    : 'A little clarity, from your documents',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Find details, connect ideas and follow the sources back to your library.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              for (final prompt in const [
                                'Find my latest electricity bill',
                                'Summarize my insurance documents',
                                'Which invoices are due soon?',
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: OutlinedButton.icon(
                                    onPressed: !state.canManageConversations
                                        ? null
                                        : () {
                                            cubit.editDraft(prompt);
                                            _focus.requestFocus();
                                          },
                                    icon: const Icon(
                                      Icons.arrow_outward,
                                      size: 18,
                                    ),
                                    label: Text(
                                      prompt,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      for (final message in state.messages)
                        Padding(
                          key: _messageKeys.putIfAbsent(
                            message.id,
                            GlobalKey.new,
                          ),
                          padding: const EdgeInsets.only(bottom: 20),
                          child: ChatMessageCard(
                            message: message,
                            onOpenDocument: widget.onOpenDocument,
                            onSendAgain:
                                state.hasActiveTurn ||
                                    state.sending ||
                                    state.uncertain ||
                                    state.deletingConversationId != null
                                ? null
                                : () {
                                    cubit.sendAgain(message);
                                    _focus.requestFocus();
                                  },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_away)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height * .15),
                child: SingleChildScrollView(
                  primary: false,
                  child: TextButton.icon(
                    onPressed: _latest,
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    label: const Text('Jump to latest'),
                  ),
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (height * .42).clamp(0, 260),
              ),
              child: SingleChildScrollView(
                primary: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.hasActiveTurn)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              key: const Key('stopChatReply'),
                              onPressed:
                                  state.stopping ||
                                      state.deletingConversationId != null
                                  ? null
                                  : cubit.stop,
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: Text(
                                state.stopping ? 'Stopping…' : 'Stop reply',
                              ),
                            ),
                          ),
                        ),
                      CallbackShortcuts(
                        bindings: {
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            control: true,
                          ): () {
                            if (state.canSend) unawaited(_send());
                          },
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            meta: true,
                          ): () {
                            if (state.canSend) unawaited(_send());
                          },
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('chatMessage'),
                                controller: _composer,
                                focusNode: _focus,
                                enabled:
                                    !state.sending &&
                                    !state.uncertain &&
                                    state.deletingConversationId == null &&
                                    state.configuration?.enabled == true,
                                minLines: 1,
                                maxLines: 5,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                keyboardType: TextInputType.multiline,
                                decoration: InputDecoration(
                                  labelText: 'Message',
                                  hintText: 'Ask about your documents…',
                                  errorText: state.draftError,
                                  errorMaxLines: 2,
                                ),
                                onChanged: cubit.editDraft,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              key: const Key('sendChatMessage'),
                              tooltip: 'Send message',
                              onPressed: state.canSend ? _send : null,
                              icon: const Icon(Icons.arrow_upward_rounded),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        compact ? 'Review answers against their sources.' : 'Review answers against their sources. Ctrl/⌘ + Enter to send.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ChatHistory extends StatelessWidget {
  const _ChatHistory({
    required this.cubit,
    required this.state,
    this.onSelected,
  });
  final ChatCubit cubit;
  final ChatState state;
  final VoidCallback? onSelected;

  Future<void> _delete(
    BuildContext context,
    ChatConversation conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Delete conversation?'),
        content: Text(
          '“${conversation.title.isEmpty ? 'New conversation' : conversation.title}” and its messages will be permanently deleted. Any active reply will stop. This cannot be undone.',
        ),
        actions: [
          TextButton(
            key: const Key('cancelDeleteChatConversation'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep conversation'),
          ),
          FilledButton(
            key: const Key('confirmDeleteChatConversation'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete conversation'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await cubit.deleteConversation(conversation);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Your conversations',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      AppProgressSlot(active: state.loadingHistory),
      if (state.deleteError != null)
        Flexible(
          child: SingleChildScrollView(
            primary: false,
            key: const Key('chatDeleteError'),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: AppNotice(message: state.deleteError!),
            ),
          ),
        ),
      Expanded(
        flex: 2,
        child: AppRefreshable(
          onRefresh:
              state.loading ||
                  state.loadingHistory ||
                  state.loadingMessages ||
                  state.sending ||
                  state.stopping ||
                  state.deletingConversationId != null
              ? null
              : cubit.load,
          child: ListView(
            key: const Key('chatHistoryList'),
            primary: false,
            children: [
              if (state.conversations.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    state.loading
                        ? 'Loading conversations…'
                        : 'Your conversations will appear here.',
                  ),
                ),
              for (final conversation in state.conversations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    key: ValueKey('chatConversation-${conversation.id}'),
                    selected: conversation.id == state.selected?.id,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Icon(
                      conversation.activeTurnId != null
                          ? Icons.schedule
                          : Icons.chat_bubble_outline,
                      size: 20,
                    ),
                    title: Text(
                      conversation.title.isEmpty
                          ? 'New conversation'
                          : conversation.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${conversation.updatedAt.toLocal().day}.${conversation.updatedAt.toLocal().month}.${conversation.updatedAt.toLocal().year}',
                    ),
                    trailing: state.deletingConversationId == conversation.id
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              semanticsLabel: 'Deleting conversation',
                            ),
                          )
                        : IconButton(
                            key: ValueKey(
                              'deleteChatConversation-${conversation.id}',
                            ),
                            tooltip: 'Delete conversation',
                            onPressed: state.canManageConversations
                                ? () => _delete(context, conversation)
                                : null,
                            icon: const Icon(Icons.delete_outline, size: 20),
                          ),
                    onTap: !state.canManageConversations
                        ? null
                        : () {
                            unawaited(cubit.select(conversation));
                            onSelected?.call();
                          },
                  ),
                ),
              if (state.conversationCursor != null)
                TextButton(
                  key: const Key('olderChatConversations'),
                  onPressed:
                      state.loadingHistory ||
                          state.loading ||
                          state.sending ||
                          state.deletingConversationId != null
                      ? null
                      : () => cubit.load(more: true),
                  child: const Text('Load older conversations'),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
