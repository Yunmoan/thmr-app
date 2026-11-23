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
      // 冷启动时网络或后端可能尚未就绪。频道目录首次请求因暂时性问题失败时，
      // 在向界面报告错误前最多重试两次。
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
  // 只有成功取得频道目录后，才能判定保存的频道已不存在。
  if (channels == null || channels.any((channel) => channel.id == stored)) {
    return stored;
  }
  return appConfig.stationId;
});
