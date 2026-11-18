import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/api/radio_api.dart';
import 'package:thmr_app/core/api/thmr_api.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/auth_provider.dart';
import 'package:thmr_app/core/state/channel_provider.dart';

class _FlakyThmrApi extends ThmrApi {
  _FlakyThmrApi(this.failures);

  final List<Object> failures;
  int calls = 0;

  @override
  Future<List<RadioChannel>> channels() async {
    calls++;
    if (calls <= failures.length) throw failures[calls - 1];
    return const [RadioChannel(id: 'touhou', name: '东方音乐电台')];
  }
}

void main() {
  test('retries a transient channel catalog failure', () async {
    final api = _FlakyThmrApi([
      DioException(
          requestOptions: RequestOptions(path: '/api/channels'),
          type: DioExceptionType.connectionError),
    ]);
    final container = ProviderContainer(overrides: [
      publicThmrApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);

    final channels = await container.read(channelCatalogProvider.future);

    expect(api.calls, 2);
    expect(channels.single.id, 'touhou');
  });

  test('does not retry permanent channel catalog errors', () async {
    final api = _FlakyThmrApi([ApiException(401, 'unauthorized')]);
    final container = ProviderContainer(overrides: [
      publicThmrApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);

    await expectLater(container.read(channelCatalogProvider.future),
        throwsA(isA<ApiException>()));
    expect(api.calls, 1);
  });
}
