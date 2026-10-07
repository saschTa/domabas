import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/document/interfaces/document_vocabulary_repository.dart';
import '../cubits/documents_cubit.dart';
import 'document_filter_dialog.dart';
import 'document_search_widgets.dart';

final class DocumentsWorkspaceToolbar extends StatefulWidget {
  const DocumentsWorkspaceToolbar({
    super.key,
    required this.cubit,
    this.vocabulary,
    this.libraryPicker,
    this.workspaceActions,
  });

  final DocumentsCubit cubit;
  final DocumentVocabularyRepository? vocabulary;
  final Widget? libraryPicker;
  final Widget? workspaceActions;

  @override
  State<DocumentsWorkspaceToolbar> createState() =>
      _DocumentsWorkspaceToolbarState();
}

final class _DocumentsWorkspaceToolbarState
    extends State<DocumentsWorkspaceToolbar> {
  final _term = TextEditingController();
  final _termFocus = FocusNode();
  final _filtersFocus = FocusNode();
  RawDialogRoute<void>? _filterRoute;
  NavigatorState? _filterNavigator;
  int _filterGeneration = 0;

  @override
  void initState() {
    super.initState();
    _term.text = widget.cubit.state.rawTerm;
    _term.addListener(_edited);
  }

  @override
  void didUpdateWidget(DocumentsWorkspaceToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cubit != widget.cubit ||
        oldWidget.vocabulary != widget.vocabulary) {
      _dismissFilters();
    }
    if (oldWidget.cubit != widget.cubit) {
      _term.removeListener(_edited);
      _term.text = widget.cubit.state.rawTerm;
      _term.addListener(_edited);
    }
  }

  @override
  void dispose() {
    _dismissFilters();
    _term.dispose();
    _termFocus.dispose();
    _filtersFocus.dispose();
    super.dispose();
  }

  void _dismissFilters() {
    _filterGeneration++;
    final route = _filterRoute;
    final navigator = _filterNavigator;
    _filterRoute = null;
    _filterNavigator = null;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && route.navigator == navigator) {
          navigator.removeRoute(route);
        }
      });
    }
  }

  void _edited() {
    final value = _term.value;
    widget.cubit.editTerm(
      value.text,
      composing: value.composing.isValid && !value.composing.isCollapsed,
    );
  }

  void _submit() {
    final composing = _term.value.composing;
    if (composing.isValid && !composing.isCollapsed) return;
    _termFocus.unfocus();
    unawaited(widget.cubit.submitSearch());
  }

  void _clear() {
    _term.clear();
    unawaited(widget.cubit.clearSearch());
  }

  Future<void> _filters() async {
    final repository = widget.vocabulary;
    if (_filterRoute != null || repository == null) return;
    final owner = widget.cubit;
    final generation = ++_filterGeneration;
    final navigator = _filterNavigator = Navigator.of(context);
    late final RawDialogRoute<void> route;
    bool owns() =>
        mounted &&
        identical(owner, widget.cubit) &&
        identical(repository, widget.vocabulary) &&
        !owner.isClosed &&
        generation == _filterGeneration &&
        _filterRoute == route &&
        navigator.mounted &&
        route.navigator == navigator &&
        route.isCurrent;
    route = RawDialogRoute<void>(
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => SafeArea(
        child: DocumentFilterDialog(
          documents: owner,
          repository: repository,
          isCurrent: owns,
          onClose: () {
            if (owns()) navigator.pop();
          },
        ),
      ),
    );
    _filterRoute = route;
    await navigator.push(route);
    if (!mounted || generation != _filterGeneration || _filterRoute != route) {
      return;
    }
    _filterRoute = null;
    _filterNavigator = null;
    if (_filtersFocus.canRequestFocus) _filtersFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DocumentsCubit, DocumentsState>(
        bloc: widget.cubit,
        listenWhen: (before, after) => before.rawTerm != after.rawTerm,
        listener: (_, state) {
          if (_term.text != state.rawTerm) {
            _term.value = TextEditingValue(
              text: state.rawTerm,
              selection: TextSelection.collapsed(offset: state.rawTerm.length),
            );
          }
        },
        builder: (context, state) => DocumentSearchControls(
          term: _term,
          termFocus: _termFocus,
          termError: state.termError,
          state: state,
          filtersFocus: _filtersFocus,
          onSubmit: _submit,
          onFilters: widget.vocabulary == null ? null : _filters,
          onClear: _clear,
          onSort: widget.cubit.setSort,
          onRemoveTag: widget.cubit.removeTag,
          onClearAddress: widget.cubit.clearAddress,
          onKindsChanged: widget.cubit.setKinds,
          onClearKinds: widget.cubit.clearKinds,
          onResetFilters: widget.cubit.resetFilters,
          searchEnabled:
              widget.cubit.capabilities.read &&
              widget.cubit.capabilities.search,
          libraryPicker: widget.libraryPicker,
          workspaceActions: widget.workspaceActions,
          actions: [
            ToggleButtons(
              borderRadius: BorderRadius.circular(10),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              isSelected: [
                state.layout == DocumentLayout.grid,
                state.layout == DocumentLayout.list,
              ],
              onPressed: (index) =>
                  widget.cubit.setLayout(DocumentLayout.values[index]),
              children: const [
                Tooltip(
                  message: 'Grid',
                  child: Icon(Icons.grid_view_rounded, size: 20),
                ),
                Tooltip(
                  message: 'List',
                  child: Icon(Icons.view_list_rounded, size: 20),
                ),
              ],
            ),
            if (state.error != null)
              IconButton(
                key: const Key('retryDocuments'),
                tooltip: 'Retry',
                onPressed:
                    state.isSaving ||
                        (state.error != null &&
                            (state.intentBlocked || state.showLoading))
                    ? null
                    : widget.cubit.retryCollection,
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
      );
}
