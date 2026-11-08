import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 대시보드에 보여 줄 시즌을 이 기기에 기억하는 보관소(게임별). 계정 설정이 아니라 이 기기의 화면 선택이다.
abstract interface class DashboardSeasonStore {
  /// [gameCode] 게임에서 고른 시즌 id. 고른 적이 없거나 읽지 못하면 null.
  Future<String?> read(String gameCode);

  /// [gameCode] 게임에서 [seasonId] 시즌을 고른다. 저장에 실패해도 화면은 이번 선택대로 보인다.
  Future<void> write(String gameCode, String seasonId);
}

/// 기기 보관소(웹은 브라우저 저장소)에 `dashboard_season_<게임 코드>` 키로 저장한다.
class SecureDashboardSeasonStore implements DashboardSeasonStore {
  SecureDashboardSeasonStore(this._storage);

  final FlutterSecureStorage _storage;

  static const String _keyPrefix = 'dashboard_season_';

  /// 보관소가 이 시간 안에 답하지 않으면 고른 적이 없는 것으로 본다(대시보드가 읽기만 기다리며 멈추지 않게).
  static const Duration _readTimeout = Duration(seconds: 2);

  @override
  Future<String?> read(String gameCode) async {
    try {
      return await _storage.read(key: '$_keyPrefix$gameCode').timeout(_readTimeout);
    } on Object catch (e) {
      debugPrint('대시보드 시즌 선택 읽기 실패(기본 시즌으로 보임): $e');
      return null;
    }
  }

  @override
  Future<void> write(String gameCode, String seasonId) async {
    try {
      await _storage.write(key: '$_keyPrefix$gameCode', value: seasonId);
    } on Object catch (e) {
      debugPrint('대시보드 시즌 선택 저장 실패(이번만 적용): $e');
    }
  }
}

/// 대시보드 시즌 선택 보관소.
final dashboardSeasonStoreProvider = Provider<DashboardSeasonStore>(
  (ref) => SecureDashboardSeasonStore(
    const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true)),
  ),
);
