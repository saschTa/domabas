import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'mobile_share_cubit.dart';
import '../ui/glacier.dart';

final class MobileShareHost extends StatelessWidget {
  const MobileShareHost({super.key, required this.shares, required this.child});
  final MobileShareCubit? shares;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cubit = shares;
    if (cubit == null) return child;
    return BlocBuilder<MobileShareCubit, MobileShareState>(
      bloc: cubit,
      builder: (context, state) {
        final batch = state.batch;
        if (batch == null) return child;
        return Column(
          children: [
            Expanded(child: child),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .55,
              ),
              child: SafeArea(
                top: false,
                child: GlacierMobileSurface(
                  glass: true,
                  radius: 20,
                  child: LayoutBuilder(
                    builder: (context, constraints) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            child: batch.error != null
                                ? GlacierMobileNotice(
                                    title: 'Shared with Domabas',
                                    message: batch.error!,
                                  )
                                : GlacierMobileIncomingShare(
                                    files: [
                                      for (final path in batch.paths)
                                        GlacierMobileReceiptValue(
                                          filename: path.split('/').last,
                                          detail: 'Staged on this device',
                                        ),
                                    ],
                                    state: state.library == null
                                        ? GlacierMobileShareState.auth
                                        : state.canUpload
                                        ? GlacierMobileShareState.ready
                                        : GlacierMobileShareState.blocked,
                                    library: state.library ?? '',
                                    showActions: false,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight * .5,
                          ),
                          child: SingleChildScrollView(
                            child: GlacierMobileActionBar(
                              children: [
                                GlacierButton(
                                  label: 'Discard',
                                  onPressed: cubit.discard,
                                ),
                                if (batch.error == null)
                                  GlacierButton(
                                    label: 'Upload',
                                    kind: GlacierButtonKind.primary,
                                    onPressed: state.canUpload
                                        ? cubit.confirm
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
