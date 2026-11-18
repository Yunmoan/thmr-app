import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/network_failure.dart';
import '../api/radio_api.dart' show ApiException;
import '../config.dart';
import '../models/models.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

final channelCatalogProvider = FutureProvider<List<RadioChannel>>((ref) async {
  final api = ref.watch(publicThmrApiProvider);
  const retryDelays = [Duration(milliseconds: 800), Duration(seconds: 2)];
  for (var attempt = 0;; attempt++) {
    try {
      return await api.channels();
    } catch (error) {
      // A cold iOS launch can fail the very first request while the network
      // or the backend is still waking up. Retry transient failures before
      // the provider caches the error for the rest of the session.
      if (attempt >= retryDelays.length || !_transientCatalogFailure(error)) {
        rethrow;
      }
      await Future<void>.delayed(retryDelays[attempt]);
    }
  }
});

bool _transientCatalogFailure(Object error) {
  if (isNetworkFailure(error) || error is FormatException) return true;
  final status = switch (error) {
    DioException(:final response) => response?.statusCode,
    ApiException(:final statusCode) => statusCode,
    _ => null,
  };
  return status == 429 || (status != null && status >= 500);
}

final activeStationIdProvider = Provider<String>((ref) {
  final stored = ref.watch(settingsProvider.select((s) => s.selectedStationId));
  final channels = ref.watch(channelCatalogProvider).valueOrNull;
  if (stored == null || !RadioChannel.isValidId(stored)) {
    return appConfig.stationId;
  }
  // Only a successful catalog can rule out a saved station.
  if (channels == null || channels.any((channel) => channel.id == stored)) {
    return stored;
  }
  return appConfig.stationId;
});
