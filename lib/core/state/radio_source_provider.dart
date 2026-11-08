import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/radio_api.dart';
import '../network/radio_sources.dart';
import 'settings_provider.dart';

export '../network/radio_sources.dart';

class RadioSourceState {
  const RadioSourceState({
    this.preference = RadioSourcePreference.automatic,
    this.selected = const RadioSource(
        RadioSourcePreference.source1, '源 1', 'https://radio.yunmoan.cn'),
    this.testing = false,
    this.tested = false,
    this.measurements = const [],
    this.testedAt,
    this.notice,
  });

  final RadioSourcePreference preference;
  final RadioSource selected;
  final bool testing;
  final bool tested;
  final List<SourceMeasurement> measurements;
  final DateTime? testedAt;
  final String? notice;

  bool get ready => preference != RadioSourcePreference.automatic || tested;
}

typedef SourceTesterFactory = RadioSourceTester Function();

class RadioSourceController extends StateNotifier<RadioSourceState> {
  RadioSourceController({
    RadioSourcePreference preference = RadioSourcePreference.automatic,
    SourceTesterFactory? testerFactory,
  })  : _testerFactory = testerFactory ?? RadioSourceTester.new,
        super(RadioSourceState(
          preference: preference,
          selected:
              radioSources[preference == RadioSourcePreference.source2 ? 1 : 0],
        ));

  final SourceTesterFactory _testerFactory;
  RadioSourceTester? _tester;
  Future<void>? _inFlight;
  int _generation = 0;

  void setPreference(RadioSourcePreference preference) {
    _generation++;
    _tester?.close();
    _tester = null;
    _inFlight = null;
    state = RadioSourceState(
      preference: preference,
      selected: preference == RadioSourcePreference.automatic
          ? state.selected
          : radioSources[preference == RadioSourcePreference.source2 ? 1 : 0],
      tested: state.tested,
      measurements: state.measurements,
      testedAt: state.testedAt,
    );
    if (preference == RadioSourcePreference.automatic) unawaited(testSources());
  }

  Future<void> ensureSelected() {
    if (state.ready) return Future.value();
    return _inFlight ?? testSources();
  }

  Future<void> testSources() {
    if (_inFlight != null) return _inFlight!;
    final future = _measure();
    _inFlight = future;
    return future;
  }

  Future<void> _measure() async {
    final generation = ++_generation;
    final tester = _testerFactory();
    _tester = tester;
    state = RadioSourceState(
      preference: state.preference,
      selected: state.selected,
      testing: true,
      tested: state.tested,
      measurements: state.measurements,
      testedAt: state.testedAt,
    );
    try {
      final results = await tester.measure();
      if (!mounted || generation != _generation) return;
      final fastest = fastestRadioSource(results);
      state = RadioSourceState(
        preference: state.preference,
        selected: state.preference == RadioSourcePreference.automatic
            ? chooseRadioSource(results, state.selected)
            : state.selected,
        tested: true,
        measurements: results,
        testedAt: DateTime.now(),
        notice: fastest == null ? '两路测速均未成功，暂用当前来源，可稍后重测或手动选择。' : null,
      );
    } catch (_) {
      if (!mounted || generation != _generation) return;
      state = RadioSourceState(
        preference: state.preference,
        selected: state.selected,
        tested: true,
        measurements: state.measurements,
        testedAt: DateTime.now(),
        notice: '测速未完成，暂用当前来源，可稍后重测。',
      );
    } finally {
      tester.close();
      if (generation == _generation) {
        _tester = null;
        _inFlight = null;
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _tester?.close();
    super.dispose();
  }
}

final radioSourceProvider =
    StateNotifierProvider<RadioSourceController, RadioSourceState>((ref) {
  final controller = RadioSourceController(
    preference: ref.read(settingsProvider).radioSource,
  );
  ref.listen(settingsProvider.select((settings) => settings.radioSource),
      (_, next) => controller.setPreference(next));
  return controller;
});

final radioApiProvider = Provider<RadioApi>((ref) => RadioApi(
      baseUrl: ref
          .watch(radioSourceProvider.select((state) => state.selected.baseUrl)),
    ));
