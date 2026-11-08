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
