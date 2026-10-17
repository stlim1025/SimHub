const String _expiredText = '만료됨';
const String _justNowText = '방금 전';

const int _secondsPerMinute = 60;
const int _minutesPerHour = 60;
const int _hoursPerDay = 24;

/// 남은 시간을 `m:ss`로 표기한다. 0 이하이면 `만료됨`.
/// 1초 미만의 나머지는 올림해, 만료 직전까지 `0:01`로 보이게 한다(순수 함수).
String formatRemaining(Duration remaining) {
  if (remaining <= Duration.zero) {
    return _expiredText;
  }
  final totalSeconds = (remaining.inMilliseconds + 999) ~/ 1000;
  final minutes = totalSeconds ~/ _secondsPerMinute;
  final seconds = totalSeconds % _secondsPerMinute;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// 경과 시간을 가장 큰 단위로 `N분 전`·`N시간 전`·`N일 전`으로 표기한다.
/// 1분 미만(또는 시계 오차로 음수)이면 `방금 전`(순수 함수).
String describeAgo(Duration elapsed) {
  if (elapsed.inMinutes < 1) {
    return _justNowText;
  }
  if (elapsed.inMinutes < _minutesPerHour) {
    return '${elapsed.inMinutes}분 전';
  }
  if (elapsed.inHours < _hoursPerDay) {
    return '${elapsed.inHours}시간 전';
  }
  return '${elapsed.inDays}일 전';
}
