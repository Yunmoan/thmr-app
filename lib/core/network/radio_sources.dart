import '../config.dart';
import 'network_probe.dart';

enum RadioSourcePreference { automatic, source1, source2 }

extension RadioSourcePreferenceLabel on RadioSourcePreference {
  String get label => switch (this) {
        RadioSourcePreference.automatic => '自动测速',
        RadioSourcePreference.source1 => '源 1',
        RadioSourcePreference.source2 => '源 2',
      };
}

String retargetRadioUrl(String currentUrl, String baseUrl) {
  final current = Uri.parse(currentUrl);
  return Uri.parse(baseUrl)
      .replace(
        path: current.path,
        query: current.hasQuery ? current.query : null,
      )
      .toString();
}

class RadioSource {
  const RadioSource(this.id, this.label, this.baseUrl);
  final RadioSourcePreference id;
  final String label;
  final String baseUrl;
}

final radioSources = List<RadioSource>.unmodifiable([
  RadioSource(RadioSourcePreference.source1, '源 1', appConfig.radioBaseUrl),
  const RadioSource(
      RadioSourcePreference.source2, '源 2', 'https://radio.zyghit.cn'),
]);

class SourceMeasurement {
  const SourceMeasurement(this.source, this.probe);
  final RadioSource source;
  final NetworkProbeResult probe;

  bool get usable =>
      probe.successful && probe.audio && probe.bytesRead >= 32768;
  double? get kilobitsPerSecond => usable && probe.elapsed.inMicroseconds > 0
      ? probe.bytesRead * 8 * 1000 / probe.elapsed.inMicroseconds
      : null;
}

RadioSource? fastestRadioSource(List<SourceMeasurement> measurements) {
  final usable = measurements.where((result) => result.usable).toList()
    ..sort((a, b) => a.probe.elapsed.compareTo(b.probe.elapsed));
  return usable.isEmpty ? null : usable.first.source;
}

/// Automatic mode only hops away from [current] when the faster source wins
/// by a meaningful margin. Probe timings differ by tens of milliseconds run
/// to run; switching the API host, covers and live stream for that noise
/// costs a reconnect and gains nothing.
RadioSource chooseRadioSource(
  List<SourceMeasurement> measurements,
  RadioSource current, {
  double minImprovement = 0.1,
}) {
  final fastest = fastestRadioSource(measurements);
  if (fastest == null || fastest.id == current.id) return current;
  SourceMeasurement? currentMeasurement;
  SourceMeasurement? fastestMeasurement;
  for (final result in measurements) {
    if (!result.usable) continue;
    if (result.source.id == current.id) currentMeasurement = result;
    if (result.source.id == fastest.id) fastestMeasurement = result;
  }
  if (currentMeasurement == null || fastestMeasurement == null) {
    return currentMeasurement == null ? fastest : current;
  }
  final elapsed = currentMeasurement.probe.elapsed.inMicroseconds;
  if (elapsed <= 0) return fastest;
  final improvement =
      1 - fastestMeasurement.probe.elapsed.inMicroseconds / elapsed;
  return improvement >= minImprovement ? fastest : current;
}

class RadioSourceTester {
  RadioSourceTester({NetworkProbe? probe}) : _probe = probe ?? NetworkProbe();
  final NetworkProbe _probe;

  Future<List<SourceMeasurement>> measure({
    String? stationId,
    String profileId = '128k',
    List<RadioSource>? sources,
  }) =>
      Future.wait((sources ?? radioSources).map((source) async {
        final uri = Uri.parse(source.baseUrl).resolve(
          '/radio/${Uri.encodeComponent(stationId ?? appConfig.stationId)}/${Uri.encodeComponent(profileId)}',
        );
        final authenticated = appConfig.streamToken.isEmpty
            ? uri
            : uri.replace(
                queryParameters: {'token': appConfig.streamToken},
              );
        return SourceMeasurement(
            source,
            await _probe.get(
              authenticated,
              maxBytes: 32768,
              resolveDns: false,
            ));
      }));

  void close() => _probe.close();
}
