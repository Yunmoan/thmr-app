import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/api/radio_api.dart';
import 'package:thmr_app/core/state/listener_provider.dart';
import 'package:thmr_app/core/state/radio_source_provider.dart';

class _ListenerApi extends RadioApi {
  final requests = <Completer<int>>[];

  @override
  Future<int> siteListeners() {
    final request = Completer<int>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  testWidgets('listener polling retains good data and follows source changes',
      (tester) async {
    final first = _ListenerApi();
    final second = _ListenerApi();
    final source = StateProvider<RadioApi>((ref) => first);
    final container = ProviderContainer(overrides: [
      radioApiProvider.overrideWith((ref) => ref.watch(source)),
    ]);

    try {
      final total = container.listen(siteListenersProvider, (_, __) {});
      expect(total.read(), isNull);
      first.requests.single.complete(17);
      await tester.pump();
      expect(total.read(), 17);

      await tester.pump(const Duration(seconds: 30));
      first.requests[1].completeError(ApiException(503, 'Unavailable'));
      await tester.pump();
      expect(total.read(), 17);

      await tester.pump(const Duration(seconds: 30));
      container.read(source.notifier).state = second;
      await tester.pump(Duration.zero);
      expect(total.read(), isNull);
      second.requests.single.complete(23);
      await tester.pump();
      first.requests[2].complete(99);
      await tester.pump();
      expect(total.read(), 23);
    } finally {
      container.dispose();
    }
  });
}
