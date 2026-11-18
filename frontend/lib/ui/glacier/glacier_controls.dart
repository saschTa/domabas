import 'package:flutter/material.dart';

import '../app_job_progress.dart';
import 'glacier_theme.dart';
import 'glacier_interaction.dart';

enum GlacierButtonKind { primary, secondary, quiet, danger }

class GlacierButton extends StatelessWidget {
  const GlacierButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = GlacierButtonKind.secondary,
    this.busy = false,
    this.focusNode,
    this.alternateLabel,
    this.showAlternateLabel = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final GlacierButtonKind kind;
  final bool busy, showAlternateLabel;
  final String? alternateLabel;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) {
    final content = Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.center,
      children: [
        if (busy)
          const AppJobSpinner()
        else if (icon != null)
          Icon(icon, size: 18),
        if (alternateLabel == null)
          Text(label, textAlign: TextAlign.center)
        else
          IndexedStack(
            alignment: Alignment.center,
            index: showAlternateLabel ? 1 : 0,
            children: [
              Text(label, textAlign: TextAlign.center),
              Text(alternateLabel!, textAlign: TextAlign.center),
            ],
          ),
      ],
    );
    final callback = busy ? null : onPressed;
    return glacierInteractionOutline(
      enabled: callback != null,
      focusOffset: context.findAncestorWidgetOfExactType<Dialog>() == null
          ? 3
          : 2,
      builder: (states, _) => switch (kind) {
        GlacierButtonKind.primary => FilledButton(
          statesController: states,
          focusNode: focusNode,
          onPressed: callback,
          child: content,
        ),
        GlacierButtonKind.danger => FilledButton.tonal(
          statesController: states,
          focusNode: focusNode,
          onPressed: callback,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
          ),
          child: content,
        ),
        GlacierButtonKind.quiet => TextButton(
          statesController: states,
          focusNode: focusNode,
          onPressed: callback,
          child: content,
        ),
        GlacierButtonKind.secondary => OutlinedButton(
          statesController: states,
          focusNode: focusNode,
          onPressed: callback,
          child: content,
        ),
      },
    );
  }
}

class GlacierIconButton extends StatelessWidget {
  const GlacierIconButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.focusNode,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) => glacierInteractionOutline(
    enabled: onPressed != null,
    focusOffset: context.findAncestorWidgetOfExactType<Dialog>() == null
        ? 3
        : 2,
    builder: (states, _) => IconButton(
      focusNode: focusNode,
      statesController: states,
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
    ),
  );
}

class GlacierChoice extends StatelessWidget {
  const GlacierChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.description,
    this.compact = false,
    this.maxLines,
  });
  final int? maxLines;
  final String label;
  final String? description;
  final bool? selected;
  final ValueChanged<bool?>? onChanged;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GlacierTokens.of(context);
    return Semantics(
      checked: selected == true,
      mixed: selected == null,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(selected != true),
      label: description == null ? label : '$label. $description',
      child: ExcludeSemantics(
        child: glacierInteractionOutline(
          enabled: onChanged != null,
          builder: (states, hovered) => Material(
            color: onChanged == null
                ? tokens.choiceLocked
                : selected != false
                ? tokens.choiceSelected
                : hovered
                ? tokens.choiceHover
                : tokens.solid.withValues(alpha: .72),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: onChanged == null
                    ? Colors.transparent
                    : hovered
                    ? tokens.accent
                    : selected != false
                    ? tokens.choiceSelectedEdge
                    : compact
                    ? tokens.choiceEdge
                    : Colors.transparent,
              ),
            ),
            child: InkWell(
              statesController: states,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              onTap: onChanged == null
                  ? null
                  : () => onChanged!(selected != true),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Row(
                  mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                  children: [
                    ExcludeFocus(
                      child: IgnorePointer(
                        child: SizedBox.square(
                          dimension: 20,
                          child: Checkbox(
                            value: selected,
                            tristate: true,
                            onChanged: onChanged,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: maxLines,
                            overflow: maxLines == null
                                ? null
                                : TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: onChanged == null
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSurface,
                            ),
                          ),
                          if (description != null)
                            Text(
                              description!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GlacierSwitchRow extends StatelessWidget {
  const GlacierSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
  });
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => glacierInteractionOutline(
    enabled: onChanged != null,
    radius: 12,
    builder: (states, hovered) {
      final tokens = GlacierTokens.of(context);
      return SwitchListTile.adaptive(
        statesController: states,
        hoverColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: onChanged == null
                ? Colors.transparent
                : hovered
                ? tokens.accent
                : value
                ? tokens.choiceSelectedEdge
                : Colors.transparent,
          ),
        ),
        tileColor: onChanged == null
            ? tokens.choiceLocked
            : value
            ? tokens.choiceSelected
            : hovered
            ? tokens.choiceHover
            : tokens.solid.withValues(alpha: .72),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Theme.of(context).colorScheme.primary
              : GlacierTokens.of(context).muted.withValues(alpha: .3),
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Theme.of(context).colorScheme.onPrimary
              : GlacierTokens.of(context).muted,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Text(label, style: Theme.of(context).textTheme.titleSmall),
        subtitle: description == null ? null : Text(description!),
        value: value,
        onChanged: onChanged,
      );
    },
  );
}

class GlacierField extends StatelessWidget {
  const GlacierField({
    super.key,
    required this.label,
    this.controller,
    this.onChanged,
    this.hint,
    this.helper,
    this.error,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.keyboardType,
  });
  final String label;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? hint, helper, error;
  final bool obscureText, enabled;
  final int maxLines;
  final TextInputType? keyboardType;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    enabled: enabled,
    obscureText: obscureText,
    maxLines: maxLines,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      errorText: error,
      helperMaxLines: 4,
      errorMaxLines: 4,
    ),
  );
}

class GlacierTag extends StatelessWidget {
  const GlacierTag({super.key, required this.label, this.onDeleted});
  final String label;
  final VoidCallback? onDeleted;
  @override
  Widget build(BuildContext context) => onDeleted == null
      ? Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              color: GlacierTokens.of(context).accent,
            ),
          ),
        )
      : InputChip(
          label: Text(label),
          onDeleted: onDeleted,
          deleteButtonTooltipMessage: 'Remove $label',
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          labelStyle: TextStyle(color: GlacierTokens.of(context).accent),
          side: BorderSide.none,
        );
}
