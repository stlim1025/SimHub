import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/profile_draft.dart';

/// 프로필·설정 REST 어댑터(04 §3.3a·3.3b, docs/14 §5). 두 호출 모두 저장된 최신 프로필을 돌려준다. 오류는 [ApiException]으로 정규화한다.
class ProfileRepository {
  ProfileRepository(this._dio);

  final Dio _dio;

  Future<AppUser> updateProfile(ProfileDraft draft) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>('/me/profile', data: draft.toJson());
      return AppUser.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 비밀번호는 요청 본문으로만 보내고 어디에도 기록하지 않는다.
  Future<AppUser> changeEmail({required String newEmail, required String currentPassword}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/me/email',
        data: {'newEmail': newEmail, 'currentPassword': currentPassword},
      );
      return AppUser.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(dioProvider)),
);
