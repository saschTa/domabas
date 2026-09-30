import 'package:flutter/material.dart';

import 'app_presenters.dart';

final class AppModelContextField extends StatelessWidget {
  const AppModelContextField({
    super.key,
    required this.controller,
    required this.fieldKey,
    required this.checkKey,
    required this.defaultKey,
    required this.scope,
    required this.enabled,
    required this.loading,
    required this.onChanged,
    required this.onCheck,
    required this.onDefault,
    this.errorText,
    this.lookupError,
    this.maxContextLength,
    this.requestedContextLength,
  });
  final TextEditingController controller;
  final Key fieldKey, checkKey, defaultKey;
  final String scope;
  final bool enabled, loading;
  final ValueChanged<String> onChanged;
  final VoidCallback? onCheck;
  final VoidCallback onDefault;
  final String? errorText, lookupError;
  final int? maxContextLength, requestedContextLength;

  @override
  Widget build(BuildContext context) {
    final maximum = maxContextLength;
    final requested = requestedContextLength;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: fieldKey,
            controller: controller,
            enabled: enabled,
            keyboardType: TextInputType.number,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Context length (tokens)',
              helperText: 'Requested text capacity per model call. Larger contexts use more memory. Default: 32,768 (32k).',
              helperMaxLines: 6,
              errorText: errorText,
              errorMaxLines: 4,
            ),
            onChanged: onChanged,
          ),
          const SizedBox(height: 8),
          Text(scope, style: Theme.of(context).textTheme.bodySmall),
          AppProgressSlot(active: loading),
          Semantics(
            liveRegion: true,
            child: Text(
              loading
                  ? 'Checking model context limit…'
                  : lookupError ??
                        (maximum == null
                            ? 'The model limit is checked before inference. Requested context is capped to the model maximum.'
                            : 'Model maximum: ${_tokens(maximum)} tokens.${requested == null ? '' : ' Effective context: ${_tokens(requested < maximum ? requested : maximum)} tokens.'}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton(
                key: checkKey,
                onPressed: enabled && !loading ? onCheck : null,
                child: Text(
                  lookupError == null
                      ? 'Check model limit'
                      : 'Retry model lookup',
                ),
              ),
              TextButton(
                key: defaultKey,
                onPressed: enabled && controller.text != '32768'
                    ? onDefault
                    : null,
                child: const Text('Use 32k default'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _tokens(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
}
