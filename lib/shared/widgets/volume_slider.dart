import 'package:flutter/material.dart';

import 'thmr_slider.dart';

/// 音量滑杆沿用 ThmrSlider 的绘制和语义逻辑，避免 Windows 页面中 OverlayPortal 遗留无障碍节点的
/// 问题。
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
