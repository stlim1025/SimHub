/// 인증 상태에 따른 리다이렉트(로그인·세션 복원). 원래 주소는 `from` 쿼리로 지켜 확인이 끝나면 돌아간다
/// — 새로고침·공유 링크(랩 상세의 Share 등)로 연 화면이 Dashboard로 튕기지 않게 한다.
library;

const String kSplashPath = '/splash';
const String kLoginPath = '/login';

/// 예전 홈 경로. 로그인 상태면 Dashboard로 보낸다.
const String _legacyHomePath = '/home';
const String _dashboardPath = '/';

/// 공유 링크 경로 접두사(`/share/laps/:lapId`). 로그인 여부와 관계없이 리다이렉트하지 않는다.
const String kSharePathPrefix = '/share/';

/// 돌아갈 주소를 담는 쿼리 이름.
const String kFromQuery = 'from';

const Set<String> _authGatePaths = {kSplashPath, kLoginPath};

/// [uri]에서 갈 곳을 정한다. 그대로 두면 null.
String? resolveAuthRedirect({required bool loading, required bool loggedIn, required Uri uri}) {
  final path = uri.path;

  // 공유 링크는 로그인 없이 본다 — 세션 복원 중·로그아웃·로그인 모두 그대로 둔다.
  if (isSharePath(path)) {
    return null;
  }

  // 세션 복원 중이면 스플래시에서 기다린다(원래 주소는 from으로).
  if (loading) {
    return path == kSplashPath ? null : _withFrom(kSplashPath, _returnTarget(uri));
  }

  if (!loggedIn) {
    return path == kLoginPath ? null : _withFrom(kLoginPath, _returnTarget(uri));
  }

  if (_authGatePaths.contains(path)) {
    return _safeFrom(uri.queryParameters[kFromQuery]) ?? _dashboardPath;
  }
  return path == _legacyHomePath ? _dashboardPath : null;
}

/// 로그인 없이 여는 공유 링크 경로인지.
bool isSharePath(String path) => path.startsWith(kSharePathPrefix);

/// 돌아갈 주소: 인증 화면이면 그 화면이 들고 있던 from, 아니면 지금 주소(쿼리 포함).
String? _returnTarget(Uri uri) => _authGatePaths.contains(uri.path)
    ? _safeFrom(uri.queryParameters[kFromQuery])
    : _safeFrom(uri.toString());

/// 앱 안 경로만 받는다(`/`로 시작, `//`·스킴 없음, 인증 화면·Dashboard 아님 — Dashboard는 기본값이라 담을 필요가 없다).
String? _safeFrom(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) {
    return null;
  }
  final path = Uri.tryParse(from)?.path;
  if (path == null || path == _dashboardPath || _authGatePaths.contains(path)) {
    return null;
  }
  return from;
}

String _withFrom(String path, String? from) =>
    from == null ? path : Uri(path: path, queryParameters: {kFromQuery: from}).toString();
