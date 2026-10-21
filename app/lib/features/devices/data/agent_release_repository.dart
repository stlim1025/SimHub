import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../domain/agent_release.dart';

/// Agent 내려받기 경로(서버 `Downloads:Directory` 폴더, 익명·REST 접두사 없음).
const String kAgentDownloadsPath = '/downloads';
const String _agentExeFileName = 'SimHubAgent.exe';
const String _agentMetadataFileName = 'SimHubAgent.json';

const Duration _connectTimeout = Duration(seconds: 10);
const Duration _receiveTimeout = Duration(seconds: 15);

/// Windows용 Agent 실행 파일 주소(`{apiBaseUrl}/downloads/SimHubAgent.exe`, 설정 내장 exe 하나). 순수 함수.
String agentDownloadUrlFor(String apiBaseUrl) => '$apiBaseUrl$kAgentDownloadsPath/$_agentExeFileName';

/// Agent 빌드 정보 조회. 정적 파일이라 인증 헤더·REST 접두사가 없는 별도 Dio를 쓴다.
class AgentReleaseRepository {
  AgentReleaseRepository(this._dio);

  final Dio _dio;

  /// 최신 빌드 정보. 파일이 없거나(404) 네트워크·형식 오류면 null — 화면은 빌드 정보만 숨긴다.
  Future<AgentRelease?> fetchLatest() async {
    try {
      final res = await _dio.get<Object?>('$kAgentDownloadsPath/$_agentMetadataFileName');
      return AgentRelease.tryParse(res.data);
    } on DioException {
      return null;
    }
  }
}

final agentReleaseRepositoryProvider = Provider<AgentReleaseRepository>(
  (ref) => AgentReleaseRepository(
    Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
      responseType: ResponseType.json,
    )),
  ),
);
