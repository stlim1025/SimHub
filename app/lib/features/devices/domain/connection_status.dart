import '../../../core/util/relative_time.dart';
import 'device_models.dart';

/// 이 시간 안에 데이터를 받았으면 "수신 중"으로 본다(docs/11 §7.3).
const Duration kReceivingWindow = Duration(minutes: 5);

/// 연결 상태 분류.
enum ConnectionKind { noDevices, neverReceived, receiving, stale }

const String _noDevicesText = '연결된 PC가 없습니다';
const String _neverReceivedText = '아직 받은 데이터가 없습니다';
const String _receivingText = '데이터 수신 중';
const String _stalePrefix = '최근 데이터 없음 · 마지막 수신';

/// 장치들 중 가장 최근의 `lastSeenAt`. 한 번도 받은 적이 없으면 null.
DateTime? _latestSeenAt(List<AgentDevice> devices) {
  DateTime? latest;
  for (final device in devices) {
    final seen = device.lastSeenAt;
    if (seen != null && (latest == null || seen.isAfter(latest))) {
      latest = seen;
    }
  }
  return latest;
}

/// [now] 시점의 연결 상태를 분류한다. 시계 오차로 `lastSeenAt`이 미래여도 수신 중으로 본다.
ConnectionKind connectionKindOf(List<AgentDevice> devices, DateTime now) {
  if (devices.isEmpty) {
    return ConnectionKind.noDevices;
  }
  final latest = _latestSeenAt(devices);
  if (latest == null) {
    return ConnectionKind.neverReceived;
  }
  return now.difference(latest) <= kReceivingWindow ? ConnectionKind.receiving : ConnectionKind.stale;
}

/// 사용자에게 보여줄 연결 상태 문구.
String connectionStatusText(List<AgentDevice> devices, DateTime now) {
  switch (connectionKindOf(devices, now)) {
    case ConnectionKind.noDevices:
      return _noDevicesText;
    case ConnectionKind.neverReceived:
      return _neverReceivedText;
    case ConnectionKind.receiving:
      return _receivingText;
    case ConnectionKind.stale:
      final elapsed = now.difference(_latestSeenAt(devices)!);
      return '$_stalePrefix ${describeAgo(elapsed)}';
  }
}
