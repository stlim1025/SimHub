import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'download_launcher_stub.dart' if (dart.library.js_interop) 'download_launcher_web.dart' as impl;

/// 파일 주소를 브라우저 내려받기로 연다. 열었으면 true, 이 플랫폼에서 열 수 없으면 false.
typedef DownloadLauncher = bool Function(String url);

/// 기본은 플랫폼 구현(웹 = 새 탭 링크, 그 밖 = 열지 않음). 테스트에서 바꿔 끼운다.
final downloadLauncherProvider = Provider<DownloadLauncher>((ref) => impl.openDownload);
