import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 액세스 토큰 보관소. **secure storage 전용**(Android Keystore/EncryptedSharedPreferences, iOS Keychain).
/// 평문 저장소(SharedPreferences 등) 금지(헌장 Security, D-25).
class TokenStore {
  TokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _keyToken = 'access_token';
  static const _keyExpiresAt = 'expires_at';

  Future<String?> readToken() => _storage.read(key: _keyToken);

  Future<void> save({required String token, required DateTime expiresAt}) async {
    await _storage.write(key: _keyToken, value: token);
    await _storage.write(key: _keyExpiresAt, value: expiresAt.toUtc().toIso8601String());
  }

  Future<DateTime?> readExpiry() async {
    final raw = await _storage.read(key: _keyExpiresAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// 토큰이 존재하고 (만료정보가 있으면) 아직 유효한지. 만료정보가 없으면 서버 401 판정에 위임한다.
  Future<bool> hasValidToken() async {
    final token = await readToken();
    if (token == null || token.isEmpty) {
      return false;
    }

    final expiry = await readExpiry();
    if (expiry == null) {
      return true;
    }

    return expiry.toUtc().isAfter(DateTime.now().toUtc());
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyExpiresAt);
  }
}

/// 안전한 기본 옵션으로 구성한 보관소 provider.
final tokenStoreProvider = Provider<TokenStore>((ref) {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  return TokenStore(storage);
});
