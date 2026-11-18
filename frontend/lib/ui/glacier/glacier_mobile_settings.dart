import 'package:flutter/material.dart';

import 'glacier_controls.dart';
import 'glacier_mobile_foundations.dart';
import 'glacier_theme.dart';
import 'glacier_settings.dart';

class GlacierMobileSettingsSection extends StatelessWidget {
  const GlacierMobileSettingsSection({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.first = false,
  });
  final String title;
  final String? description;
  final Widget child;
  final bool first;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: first ? 12 : 24),
    child: GlacierSettingsSection(
      title: title,
      description: description,
      child: child,
    ),
  );
}

class GlacierMobileSettingsForm extends StatelessWidget {
  const GlacierMobileSettingsForm({
    super.key,
    required this.children,
    required this.submitLabel,
    required this.onSubmit,
    this.feedback,
    this.enabled = true,
    this.busy = false,
  });
  final List<Widget> children;
  final String submitLabel;
  final VoidCallback? onSubmit;
  final Widget? feedback;
  final bool enabled, busy;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ?feedback,
      ExcludeFocus(
        excluding: !enabled,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0 &&
                    children[i] is GlacierMobileField &&
                    children[i - 1] is GlacierMobileField)
                  const SizedBox(height: 12),
                children[i],
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      GlacierButton(
        label: submitLabel,
        onPressed: enabled ? onSubmit : null,
        busy: busy,
      ),
    ],
  );
}

class GlacierMobileFieldGroup extends StatelessWidget {
  const GlacierMobileFieldGroup({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final paired =
          constraints.maxWidth >= 492 &&
          MediaQuery.textScalerOf(context).scale(15) <= 22;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children)
            SizedBox(
              width: paired
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth,
              child: child,
            ),
        ],
      );
    },
  );
}

class GlacierMobileSelectField extends StatelessWidget {
  const GlacierMobileSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label, value;
  final List<String> options;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13.5, height: 1.2),
          ),
        ),
        const SizedBox(height: 7),
        Semantics(
          label: label,
          child: DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            selectedItemBuilder: (context) => [
              for (final option in options)
                Text(
                  option,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
            ],
            disabledHint: Text(
              value,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            style: TextStyle(
              fontSize: 15,
              height: 1.2,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            items: [
              for (final option in options)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: onChanged == null
                ? null
                : (value) {
                    if (value != null) onChanged!(value);
                  },
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.all(12),
              filled: true,
              fillColor: GlacierTokens.of(context).surface,
              constraints: const BoxConstraints(minHeight: 50),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class GlacierMobilePermissionChoice extends StatelessWidget {
  const GlacierMobilePermissionChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.detail,
  });
  final String label;
  final String? detail;
  final bool selected;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    final tokens = GlacierTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        checked: selected,
        enabled: onChanged != null,
        label: detail == null ? label : '$label. $detail',
        onTap: onChanged == null ? null : () => onChanged!(!selected),
        child: ExcludeSemantics(
          child: Material(
            color: selected
                ? tokens.accent.withValues(alpha: .10)
                : tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
              side: BorderSide(color: selected ? tokens.accent : tokens.border),
            ),
            child: InkWell(
              onTap: onChanged == null ? null : () => onChanged!(!selected),
              borderRadius: BorderRadius.circular(11),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (detail != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                detail!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: selected ? tokens.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected ? tokens.accent : tokens.muted,
                            width: 1.5,
                          ),
                        ),
                        child: selected
                            ? Icon(
                                Icons.check,
                                size: 15,
                                color: Theme.of(context).colorScheme.onPrimary,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GlacierMobileDisclosure extends StatefulWidget {
  const GlacierMobileDisclosure({
    super.key,
    required this.label,
    required this.child,
    this.initiallyExpanded = false,
  });
  final String label;
  final Widget child;
  final bool initiallyExpanded;
  @override
  State<GlacierMobileDisclosure> createState() =>
      _GlacierMobileDisclosureState();
}

class _GlacierMobileDisclosureState extends State<GlacierMobileDisclosure> {
  late bool expanded = widget.initiallyExpanded;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        expanded: expanded,
        child: TextButton(
          onPressed: () => setState(() => expanded = !expanded),
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          ),
          child: Row(
            children: [
              Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                size: 20,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(widget.label)),
            ],
          ),
        ),
      ),
      AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: expanded ? widget.child : const SizedBox.shrink(),
      ),
    ],
  );
}

class GlacierMobileAppearance extends StatelessWidget {
  const GlacierMobileAppearance({
    super.key,
    required this.mode,
    required this.background,
    required this.reduceTransparency,
    required this.reduceMotion,
    required this.onModeChanged,
    required this.onBackgroundChanged,
    required this.onTransparencyChanged,
    required this.onMotionChanged,
  });
  final String mode, background;
  final bool reduceTransparency, reduceMotion;
  final ValueChanged<String> onModeChanged, onBackgroundChanged;
  final ValueChanged<bool> onTransparencyChanged, onMotionChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierMobileSettingsSection(
        title: 'Appearance',
        first: true,
        child: GlacierMobileActionBar(
          children: [
            for (final value in ['System', 'Light', 'Dark'])
              MergeSemantics(
                child: Semantics(
                  selected: mode == value.toLowerCase(),
                  checked: mode == value.toLowerCase(),
                  inMutuallyExclusiveGroup: true,
                  container: true,
                  child: GlacierButton(
                    label: value,
                    kind: mode == value.toLowerCase()
                        ? GlacierButtonKind.primary
                        : GlacierButtonKind.secondary,
                    onPressed: () => onModeChanged(value.toLowerCase()),
                  ),
                ),
              ),
          ],
        ),
      ),
      GlacierMobileSettingsSection(
        title: 'Background',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlacierMobileActionBar(
              children: [
                for (final value in ['Calm', 'Activity'])
                  MergeSemantics(
                    child: Semantics(
                      selected: background == value.toLowerCase(),
                      checked: background == value.toLowerCase(),
                      inMutuallyExclusiveGroup: true,
                      container: true,
                      child: GlacierButton(
                        label: value,
                        kind: background == value.toLowerCase()
                            ? GlacierButtonKind.primary
                            : GlacierButtonKind.secondary,
                        onPressed: () =>
                            onBackgroundChanged(value.toLowerCase()),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 68,
              child: CustomPaint(
                painter: _MobileActivityPreview(
                  GlacierTokens.of(context).accent,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'A softened trace of indexing and jobs over time. Your documents stay in the foreground.',
              style: TextStyle(color: GlacierTokens.of(context).muted),
            ),
          ],
        ),
      ),
      GlacierMobileSettingsSection(
        title: 'Comfort',
        child: Column(
          children: [
            GlacierMobilePermissionChoice(
              label: 'Reduce transparency',
              detail: 'Use solid surfaces with the same borders and contrast.',
              selected: reduceTransparency,
              onChanged: onTransparencyChanged,
            ),
            GlacierMobilePermissionChoice(
              label: 'Reduce motion',
              detail: 'Use gentle fades instead of sliding transitions.',
              selected: reduceMotion,
              onChanged: onMotionChanged,
            ),
          ],
        ),
      ),
    ],
  );
}

class _MobileActivityPreview extends CustomPainter {
  const _MobileActivityPreview(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = color.withValues(alpha: .16)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 50) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 15.0; y < size.height; y += 25) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    const values = [.82, .76, .80, .54, .59, .38, .45, .21, .28, .14, .25, .09];
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        size.width * i / (values.length - 1),
        size.height * values[i],
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_MobileActivityPreview oldDelegate) =>
      color != oldDelegate.color;
}

class GlacierMobileProviderFields extends StatelessWidget {
  const GlacierMobileProviderFields({
    super.key,
    required this.provider,
    required this.model,
    required this.baseUrl,
    required this.onProviderChanged,
    required this.onModelChanged,
    required this.onBaseUrlChanged,
    required this.onKeyChanged,
    required this.removeKey,
    required this.onRemoveKeyChanged,
    this.extraction = false,
    this.compatibility = false,
    this.onCompatibilityChanged,
  });
  final String provider, model, baseUrl;
  final ValueChanged<String> onProviderChanged,
      onModelChanged,
      onBaseUrlChanged,
      onKeyChanged;
  final bool removeKey, extraction, compatibility;
  final ValueChanged<bool> onRemoveKeyChanged;
  final ValueChanged<bool>? onCompatibilityChanged;
  @override
  Widget build(BuildContext context) => GlacierMobileSettingsSection(
    title: 'Model provider',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (provider == 'External service')
          const GlacierMobileNotice(
            title: 'External processing',
            message: 'Extracted document text is sent to the configured external service for this operation.',
          ),
        GlacierMobileSelectField(
          label: 'Provider',
          value: provider,
          options: const ['Internal Ollama', 'External service'],
          onChanged: onProviderChanged,
        ),
        GlacierMobileField(
          label: 'Model',
          initialValue: model,
          onChanged: onModelChanged,
        ),
        GlacierMobileDisclosure(
          label: 'External service and credentials',
          initiallyExpanded: provider == 'External service',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlacierMobileFieldGroup(
                children: [
                  GlacierMobileField(
                    label: 'API base URL',
                    initialValue: baseUrl,
                    onChanged: onBaseUrlChanged,
                    keyboardType: TextInputType.url,
                  ),
                  GlacierMobileField(
                    label: 'Replacement API key',
                    obscureText: true,
                    onChanged: onKeyChanged,
                  ),
                ],
              ),
              const Text(
                'A stored key is configured. Leave blank to keep it for this address. A changed address requires reviewing its credentials.',
              ),
              GlacierMobilePermissionChoice(
                label: 'Remove stored API key',
                selected: removeKey,
                onChanged: onRemoveKeyChanged,
              ),
              if (extraction)
                GlacierMobilePermissionChoice(
                  label: 'LM Studio compatibility mode',
                  detail: 'Use compatibility behavior for a local LM Studio endpoint.',
                  selected: compatibility,
                  onChanged: onCompatibilityChanged,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class GlacierMobileImportOutcome extends StatelessWidget {
  const GlacierMobileImportOutcome({
    super.key,
    required this.title,
    required this.outcome,
    required this.detail,
    this.onOpen,
    this.attention = false,
  });
  final String title, outcome, detail;
  final VoidCallback? onOpen;
  final bool attention;
  @override
  Widget build(BuildContext context) => GlacierMobileRecordRow(
    title: title,
    detail: '$outcome · $detail',
    icon: attention ? Icons.warning_amber : Icons.description_outlined,
    onTap: onOpen,
  );
}
