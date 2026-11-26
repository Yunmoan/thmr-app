import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';

void main() {
  testWidgets('iOS 主题启用无水波纹反馈与聚焦强调边框', (tester) async {
    final theme = ThmrTheme.light();
    expect(theme.splashFactory, NoSplash.splashFactory);
    expect(theme.highlightColor, isNotNull);

    final focused =
        theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
    final enabled =
        theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
    expect(focused.borderSide.color, isNot(enabled.borderSide.color));
    expect(focused.borderSide.width, greaterThan(enabled.borderSide.width));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
