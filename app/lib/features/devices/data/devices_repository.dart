import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../domain/device_models.dart';

/// Agent 연결 코드·장치 REST 어댑터(docs/11 §8).
class DevicesRepository {
  DevicesRepository(this._dio);

  final Dio _dio;

  /// 새 1회용 연결 코드를 발급한다. 한도(사용자당 분당 10회)를 넘으면 429.
  Future<PairingCode> issuePairingCode() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/me/agent-pairing-codes');
      return PairingCode.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 내 장치 목록(서버가 생성 시각 내림차순으로 돌려준다).
  Future<List<AgentDevice>> getDevices() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/me/agent-devices');
      return (res.data!['items'] as List<dynamic>)
          .map((e) => AgentDevice.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 장치 연결을 해제한다. 타인 장치는 403, 없는 장치는 404.
  Future<void> revoke(String deviceId) async {
    try {
      await _dio.delete<void>('/me/agent-devices/$deviceId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final devicesRepositoryProvider = Provider<DevicesRepository>(
  (ref) => DevicesRepository(ref.watch(dioProvider)),
);
