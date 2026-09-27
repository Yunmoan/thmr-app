import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// A failed request is not always a lost connection: HTTP errors are handled
/// separately so stale cache cannot hide authentication or server errors.
bool isNetworkFailure(Object error) {
  if (error is SocketException || error is TimeoutException) return true;
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        true,
      _ => false,
    };
  }
  return false;
}
