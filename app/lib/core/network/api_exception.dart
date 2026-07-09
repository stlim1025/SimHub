import 'package:dio/dio.dart';

/// 사용자에게 노출 가능한 API 오류. 서버 내부정보/스택은 담지 않고 친화 메시지만 전달한다(헌장 Security).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// DioException을 사용자 메시지로 매핑한다. RFC7807 Problem Details의 `detail`/`title`을 우선 사용.
  factory ApiException.fromDio(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;

    if (data is Map) {
      final detail = data['detail'] ?? data['title'];
      if (detail is String && detail.isNotEmpty) {
        return ApiException(detail, statusCode: status);
      }
    }

    final message = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        '서버 응답이 지연되고 있어요. 잠시 후 다시 시도해 주세요.',
      DioExceptionType.connectionError =>
        '서버에 연결할 수 없어요. 네트워크를 확인해 주세요.',
      _ => switch (status) {
          400 => '요청이 올바르지 않아요.',
          401 => '로그인이 필요해요.',
          403 => '권한이 없어요.',
          404 => '대상을 찾을 수 없어요.',
          409 => '이미 처리된 요청이거나 충돌이 발생했어요.',
          _ => '문제가 발생했어요. 잠시 후 다시 시도해 주세요.',
        },
    };

    return ApiException(message, statusCode: status);
  }

  @override
  String toString() => message;
}
