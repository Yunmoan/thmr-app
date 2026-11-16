import 'package:flutter/material.dart';

import 'thmr_slider.dart';

/// Volume control without Slider's OverlayPortal, which can produce orphaned
/// accessibility nodes on Windows when shown in a pushed route.
class VolumeSlider extends StatelessWidget {
  const VolumeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 34,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) => ThmrSlider(
        value: value,
        min: 0,
        max: 100,
        step: 5,
        semanticsLabel: '音量',
        formatValue: (value) => '${value.round()}%',
        onChanged: onChanged,
        height: height,
      );
}
