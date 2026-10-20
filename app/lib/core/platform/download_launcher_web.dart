import 'package:web/web.dart' as web;

const String _newTabTarget = '_blank';
const String _noOpener = 'noopener';

/// 웹: 새 탭 링크를 눌러 내려받는다. 서버가 `Content-Disposition: attachment`를 붙이므로 브라우저는 파일로 저장하고,
/// 파일이 없어 오류가 나더라도 앱 화면은 그대로 남는다.
bool openDownload(String url) {
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..target = _newTabTarget
    ..rel = _noOpener;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  return true;
}
