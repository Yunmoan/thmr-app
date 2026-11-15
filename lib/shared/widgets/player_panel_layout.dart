import 'package:flutter/material.dart';

import 'thmr_panel.dart';

/// Shared geometry for the loaded player and its skeleton.
class PlayerPanelLayout extends StatelessWidget {
  const PlayerPanelLayout(
      {super.key,
      required this.header,
      required this.playback,
      required this.volume,
      this.quality});
  final Widget header;
  final Widget playback;
  final Widget volume;
  final Widget? quality;

  @override
  Widget build(BuildContext context) => ThmrPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 14),
              playback,
              const SizedBox(height: 12),
              volume,
              if (quality != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                quality!,
              ],
            ]),
      );
}
