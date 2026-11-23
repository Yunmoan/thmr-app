import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// 判断是否为连接或超时错误。HTTP 响应错误由调用方单独处理，避免把服务端响应误判为离线。
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
