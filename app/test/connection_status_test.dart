import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/devices/domain/connection_status.dart';
import 'package:simcenter_app/features/devices/domain/device_models.dart';

final _now = DateTime.utc(2026, 10, 17, 12);

AgentDevice _device(String id, {DateTime? lastSeenAt}) => AgentDevice(
      deviceId: id,
      name: 'PC-$id',
      lastSeenAt: lastSeenAt,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  test('connectionStatusText', () {
    expect(connectionStatusText(const [], _now), '연결된 PC가 없습니다');
    expect(
      connectionStatusText([_device('a'), _device('b')], _now),
      '아직 받은 데이터가 없습니다',
    );
    expect(
      connectionStatusText(
        [_device('a', lastSeenAt: _now.subtract(const Duration(minutes: 4)))],
        _now,
      ),
      '데이터 수신 중',
    );
    expect(
      connectionStatusText(
        [_device('a', lastSeenAt: _now.subtract(const Duration(days: 82)))],
        _now,
      ),
      '최근 데이터 없음 · 마지막 수신 82일 전',
    );
  });

  group('connectionKindOf', () {
    test('장치가 없으면 noDevices', () {
      expect(connectionKindOf(const [], _now), ConnectionKind.noDevices);
    });

    test('lastSeenAt이 모두 null이면 neverReceived', () {
      expect(connectionKindOf([_device('a'), _device('b')], _now), ConnectionKind.neverReceived);
    });

    test('수신 창(5분) 안이면 receiving, 정확히 5분도 포함한다', () {
      expect(kReceivingWindow, const Duration(minutes: 5));
      expect(
        connectionKindOf([_device('a', lastSeenAt: _now.subtract(kReceivingWindow))], _now),
        ConnectionKind.receiving,
      );
    });

    test('수신 창을 1초라도 넘으면 stale', () {
      final seen = _now.subtract(kReceivingWindow + const Duration(seconds: 1));
      expect(connectionKindOf([_device('a', lastSeenAt: seen)], _now), ConnectionKind.stale);
    });

    test('여러 장치 중 가장 최근 lastSeenAt으로 판단한다', () {
      final devices = [
        _device('old', lastSeenAt: _now.subtract(const Duration(days: 3))),
        _device('new', lastSeenAt: _now.subtract(const Duration(minutes: 1))),
        _device('never'),
      ];
      expect(connectionKindOf(devices, _now), ConnectionKind.receiving);
    });

    test('lastSeenAt이 now보다 미래여도(시계 오차) receiving', () {
      final seen = _now.add(const Duration(seconds: 20));
      expect(connectionKindOf([_device('a', lastSeenAt: seen)], _now), ConnectionKind.receiving);
    });

    test('분·시간 단위 문구도 만든다', () {
      expect(
        connectionStatusText(
          [_device('a', lastSeenAt: _now.subtract(const Duration(minutes: 30)))],
          _now,
        ),
        '최근 데이터 없음 · 마지막 수신 30분 전',
      );
      expect(
        connectionStatusText(
          [_device('a', lastSeenAt: _now.subtract(const Duration(hours: 7)))],
          _now,
        ),
        '최근 데이터 없음 · 마지막 수신 7시간 전',
      );
    });
  });
}
