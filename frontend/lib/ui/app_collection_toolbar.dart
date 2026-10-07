import 'package:flutter/material.dart';

final class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText = 'Search',
    this.tooltip,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTapOutside,
    this.onClear,
    this.enabled = true,
    this.fieldKey,
    this.clearKey,
    this.submitKey,
    this.submittingBlocked = false,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final String? tooltip, errorText;
  final ValueChanged<String>? onChanged, onSubmitted;
  final VoidCallback? onEditingComplete, onClear;
  final TapRegionCallback? onTapOutside;
  final bool enabled, submittingBlocked;
  final Key? fieldKey, clearKey, submitKey;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          key: fieldKey,
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          onEditingComplete: onEditingComplete,
          onTapOutside: onTapOutside,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: hintText,
            errorText: errorText,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            prefixIcon: IconButton(
              key: submitKey,
              tooltip: tooltip ?? 'Search',
              onPressed: enabled && !submittingBlocked && onSubmitted != null
                  ? () => onSubmitted!(controller.text)
                  : null,
              icon: const Icon(Icons.search_rounded, size: 20),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 48,
              minHeight: 48,
            ),
            suffixIcon: value.text.isNotEmpty && onClear != null
                ? IconButton(
                    key: clearKey,
                    tooltip: 'Clear search',
                    onPressed: enabled ? onClear : null,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  )
                : null,
          ),
        ),
      );
}

final class AppCollectionToolbar extends StatelessWidget {
  const AppCollectionToolbar({
    super.key,
    this.search,
    this.actions = const [],
    this.summary,
    this.libraryPicker,
    this.workspaceActions,
  });

  final Widget? search, summary, libraryPicker, workspaceActions;
  final List<Widget> actions;

  Widget _controls() => SingleChildScrollView(
    key: const Key('collectionToolbarControls'),
    primary: false,
    scrollDirection: Axis.horizontal,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          actions[index],
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final enlarged = MediaQuery.textScalerOf(context).scale(14) > 20;
      final oneRow = width >= 1050 && !enlarged;
      final libraryWidth = (width * .42).clamp(
        0.0,
        width < 420 ? 132.0 : 208.0,
      );
      final library = libraryPicker == null
          ? null
          : SizedBox(
              key: const Key('collectionToolbarLibrary'),
              width: libraryWidth,
              child: libraryPicker,
            );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            key: const Key('collectionToolbarPrimary'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (search != null) Expanded(child: search!),
              if (oneRow && actions.isNotEmpty) ...[
                if (search != null) const SizedBox(width: 12),
                Expanded(flex: 2, child: _controls()),
              ],
              if (search == null && (!oneRow || actions.isEmpty))
                const Spacer(),
              if (oneRow && workspaceActions != null) ...[
                const SizedBox(width: 12),
                workspaceActions!,
              ],
              if (library != null) ...[const SizedBox(width: 12), library],
            ],
          ),
          if (!oneRow && (actions.isNotEmpty || workspaceActions != null)) ...[
            const SizedBox(height: 8),
            Row(
              key: const Key('collectionToolbarSecondary'),
              children: [
                Expanded(child: _controls()),
                if (workspaceActions != null) ...[
                  const SizedBox(width: 8),
                  workspaceActions!,
                ],
              ],
            ),
          ],
          if (summary != null) ...[const SizedBox(height: 8), summary!],
        ],
      );
    },
  );
}
