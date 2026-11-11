import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/radio_api.dart';
import 'radio_source_provider.dart';

final siteListenersProvider =
    StateNotifierProvider.autoDispose<SiteListenersPoller, int?>((ref) {
  return SiteListenersPoller(ref.watch(radioApiProvider));
});

class SiteListenersPoller extends StateNotifier<int?> {
  SiteListenersPoller(this._api) : super(null) {
    unawaited(_refresh());
  }

  final RadioApi _api;
  Timer? _timer;

  Future<void> _refresh() async {
    try {
      final total = await _api.siteListeners();
      if (mounted) state = total;
    } catch (_) {
      // Keep the latest total from this source through a transient failure.
    } finally {
      if (mounted) _timer = Timer(const Duration(seconds: 30), _refresh);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
