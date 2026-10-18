import 'package:dio/dio.dart';

/// 사용자에게 노출 가능한 API 오류. 서버 내부정보/스택은 담지 않고 친화 메시지만 전달한다(헌장 Security).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.fieldErrors = const {}});

  final String message;
  final int? statusCode;

  /// 검증 실패(400)의 필드별 첫 메시지(`errors.<필드>[0]`, 04 §1). 예: `{'currentPassword': '현재 비밀번호가 올바르지 않습니다.'}`.
  final Map<String, String> fieldErrors;

  /// 우리 서버 예외 미들웨어가 만든 Problem Details의 `type` 접두사(04 §1). 이 문서만 사용자에게 보일 문구로 믿는다.
  static const _problemTypePrefix = 'https://simcenter/errors/';

  /// DioException을 사용자 메시지로 매핑한다. 우리 서버의 RFC7807 Problem Details면 필드 오류 → `detail` → `title` 순으로 쓴다
  /// (검증 실패의 `detail`은 늘 "Validation failed."라 필드 메시지가 더 쓸모 있다).
  /// 그 밖의 오류 본문(예: ASP.NET 모델 바인딩의 `$.field` 키·.NET 타입 이름이 든 메시지)은 보이지 않고 상태 코드별 일반 메시지를 쓴다.
  factory ApiException.fromDio(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;

    if (data is Map && _isSimCenterProblem(data)) {
      final fields = _fieldErrors(data['errors']);
      final detail = data['detail'] ?? data['title'];
      final message = fields.isNotEmpty ? fields.values.first : detail;
      if (message is String && message.isNotEmpty) {
        return ApiException(message, statusCode: status, fieldErrors: fields);
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
          429 => '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.',
          _ => '문제가 발생했어요. 잠시 후 다시 시도해 주세요.',
        },
    };

    return ApiException(message, statusCode: status);
  }

  static bool _isSimCenterProblem(Map<dynamic, dynamic> data) {
    final type = data['type'];
    return type is String && type.startsWith(_problemTypePrefix);
  }

  /// `errors` 객체 → 필드별 첫 메시지. 형식이 다르면 빈 맵.
  static Map<String, String> _fieldErrors(Object? errors) {
    if (errors is! Map) {
      return const {};
    }
    return {
      for (final entry in errors.entries)
        if (entry.value is List && (entry.value as List).isNotEmpty && (entry.value as List).first is String)
          '${entry.key}': (entry.value as List).first as String,
    };
  }

  @override
  String toString() => message;
}
