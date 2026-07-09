/// 밀리초 랩타임을 `m:ss.mmm` 형식으로 표기한다(순수 함수, 단위 테스트 대상).
String formatLapTime(int milliseconds) {
  if (milliseconds < 0) {
    return '--:--.---';
  }
  final minutes = milliseconds ~/ 60000;
  final seconds = (milliseconds ~/ 1000) % 60;
  final millis = milliseconds % 1000;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}';
}
