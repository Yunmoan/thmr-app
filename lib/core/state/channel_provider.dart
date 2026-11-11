import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../models/models.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

final channelCatalogProvider = FutureProvider<List<RadioChannel>>((ref) {
  return ref.watch(publicThmrApiProvider).channels();
});

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
