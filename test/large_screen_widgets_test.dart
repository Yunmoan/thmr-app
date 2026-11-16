import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/large_screen_settings.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/features/large_screen/large_screen_widget_editor.dart';
import 'package:thmr_app/features/large_screen/large_screen_widgets.dart';

class _Station extends StateNotifier<StationUiState> implements StationPoller {
  _Station()
      : super(StationUiState(
            initialLoading: false,
            status: StationStatus.fromJson({
              'station': {'id': 'test', 'name': '原曲频道'},
              'current': {
                'trackId': 'one',
                'title': '春色小径',
                'artist': '上海アリス幻樂団'
              }
            })));
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('date, 12-hour clocks and Beijing midnight use the selected timezone',
      () {
    final time = DateTime.utc(2026, 12, 31, 16, 7, 9);
    const clock = LargeScreenWidgetSettings(
        id: 'clock',
        format: 'HH:mm:ss',
        timezone: LargeScreenWidgetTimezone.beijing);
    expect(largeScreenWidgetText(clock, time), '00:07:09');
    expect(largeScreenWidgetText(clock.copyWith(format: 'h:mm a'), time),
        '12:07 上午');
    expect(
        largeScreenWidgetText(
            clock.copyWith(
                kind: LargeScreenWidgetKind.date, format: 'yyyy年M月d日 EEEE'),
            time),
        '2027年1月1日 星期五');
    expect(
        largeScreenWidgetText(
            clock.copyWith(timezone: LargeScreenWidgetTimezone.utc), time),
        '16:07:09');
    expect(formatLargeScreenDate(DateTime(2026, 11, 16, 12), 'hh:mm a'),
        '12:00 下午');
  });

  test('text tags update metadata without interpreting the inserted value', () {
    const text = LargeScreenWidgetSettings(
        id: 'text',
        kind: LargeScreenWidgetKind.text,
        text: '{title} · {artist} / {channel} · {date} {weekday}',
        timezone: LargeScreenWidgetTimezone.utc);
    expect(
        largeScreenWidgetText(text, DateTime.utc(2026, 11, 16),
            title: 'title {date}', artist: 'ZUN', channel: '原曲频道'),
        'title {date} · ZUN / 原曲频道 · 2026-11-16 星期一');
    expect(text.needsClock, isTrue);
    expect(text.copyWith(text: '东方音乐交流会').needsClock, isFalse);
  });

  test('custom appearance and all component fields survive a restart',
      () async {
    SharedPreferences.setMockInitialValues({});
    final controller = LargeScreenSettingsController();
    addTearDown(controller.dispose);
    await controller.ready;
    final chosen = const LargeScreenSettings()
        .copyWith(contentMargin: 64, illustrationOpacity: .4, widgets: const [
      LargeScreenWidgetSettings(
          id: 'custom',
          kind: LargeScreenWidgetKind.text,
          position: LargeScreenWidgetPosition.bottomLeft,
          text: '{title} · {artist}',
          format: 'HH:mm:ss',
          fontSize: 64,
          font: LargeScreenWidgetFont.mono,
          weight: 800,
          tone: LargeScreenWidgetTone.custom,
          color: 0xFF445566,
          decoration: LargeScreenWidgetDecoration.rule,
          timezone: LargeScreenWidgetTimezone.utc,
          italic: true,
          letterSpacing: 4,
          opacity: .6,
          maxLines: 4,
          enabled: false)
    ]);
    await controller.update(chosen);
    final restored = LargeScreenSettingsController();
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.state.toJson(), chosen.toJson());
  });

  test('old preferences and malformed components keep a bounded unique layout',
      () {
    expect(LargeScreenSettings.fromJson({}).widgets, isEmpty);
    final settings = LargeScreenSettings.fromJson({
      'widgets': [
        {
          'id': 'widget-1-0',
          'fontSize': 999,
          'opacity': -100,
          'font': 'missing'
        },
        {'id': 'widget-1-0'},
        {'id': ''},
        'bad entry',
        for (var i = 0; i < 12; i++) {'id': 'duplicate'},
      ]
    });
    expect(settings.widgets.length, 8);
    expect(settings.widgets.map((w) => w.id).toSet().length, 8);
    expect(settings.widgets.first.fontSize, 96);
    expect(settings.widgets.first.opacity, .3);
    expect(settings.widgets.first.font, LargeScreenWidgetFont.inherit);
  });

  for (final width in [280.0, 760.0]) {
    testWidgets(
        'components can be added, edited, duplicated and removed at $width',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
          overrides: [stationProvider.overrideWith((ref) => _Station())]);
      addTearDown(container.dispose);
      await container.read(largeScreenSettingsProvider.notifier).ready;
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: ThemeData(extensions: [ThmrTokens.reimuLight]),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(width < 300 ? 2 : 1)),
                  child: child!),
              home: const Scaffold(
                  body: SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: LargeScreenWidgetEditor())))));
      await tester.tap(find.byTooltip('添加小组件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('时间').last);
      await tester.pumpAndSettle();
      expect(container.read(largeScreenSettingsProvider).widgets.single.kind,
          LargeScreenWidgetKind.clock);
      final seconds = find.widgetWithText(ChoiceChip, '显示秒');
      await tester.ensureVisible(seconds);
      await tester.tap(seconds);
      await tester.pumpAndSettle();
      expect(container.read(largeScreenSettingsProvider).widgets.single.format,
          'HH:mm:ss');
      final formatInput = tester.widget<TextField>(find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == 'HH:mm:ss'));
      expect(formatInput.controller!.text, 'HH:mm:ss');
      await tester.ensureVisible(find.byTooltip('删除小组件'));
      await tester.tap(find.byTooltip('删除小组件'));
      await tester.pumpAndSettle();
      expect(container.read(largeScreenSettingsProvider).widgets, isEmpty);
      await tester.ensureVisible(find.byTooltip('添加小组件'));
      await tester.tap(find.byTooltip('添加小组件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文本').last);
      await tester.pumpAndSettle();
      final input = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '输入要显示的文字');
      await tester.ensureVisible(input);
      await tester.enterText(input, '正在放送：');
      await tester.ensureVisible(find.text('插入曲名'));
      await tester.tap(find.text('插入曲名'));
      await tester.pumpAndSettle();
      expect(container.read(largeScreenSettingsProvider).widgets.single.text,
          '正在放送：{title}');
      expect(find.text('正在放送：春色小径', skipOffstage: false), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('复制小组件'));
      await tester.tap(find.byTooltip('复制小组件'));
      await tester.pumpAndSettle();
      final saved = container.read(largeScreenSettingsProvider).widgets;
      expect(saved.length, 2);
      expect(saved.first.id, isNot(saved.last.id));
      expect(saved.first.text, saved.last.text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('hidden clocks stop rebuilding and resume with current data',
      (tester) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await tester.pumpWidget(MaterialApp(
        home: ValueListenableBuilder(
            valueListenable: active,
            builder: (_, visible, __) => TickerMode(
                enabled: visible,
                child: const SizedBox(
                    width: 700,
                    height: 100,
                    child: LargeScreenWidgetStrip(components: [
                      LargeScreenWidgetSettings(id: 'time', format: 'HH:mm:ss')
                    ], station: StationUiState(), atTop: true))))));
    await tester.pump();
    active.value = false;
    await tester.pump();
    final before = tester.widget<Text>(find.byType(Text)).data;
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widget<Text>(find.byType(Text)).data, before);
    expect(tester.binding.hasScheduledFrame, isFalse);
    active.value = true;
    await tester.pump();
    expect(find.byType(LargeScreenWidgetView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
