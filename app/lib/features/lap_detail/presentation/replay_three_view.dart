// 다시보기 3D 화면(three.js) 진입점: 웹이면 WebGL 그림, 그 밖(테스트·휴대폰 앱)이면 [ReplayThreeView.fallback]을 그대로 그린다.
export 'replay_three_view_stub.dart' if (dart.library.js_interop) 'replay_three_view_web.dart';
