import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/features/auth/application/auth_controller.dart';
import 'package:simcenter_app/features/devices/application/devices_providers.dart';
import 'package:simcenter_app/features/devices/data/devices_repository.dart';
import 'package:simcenter_app/features/devices/domain/device_models.dart';

import 'support/fakes.dart';

final _expiresAt = DateTime.utc(2026, 10, 17, 12, 10);

PairingCode _code(int n) => PairingCode(code: 'CODE-$n', expiresAt: _expiresAt);

Future<ProviderContainer> _container(FakeDevicesRepository repo) async {
  final container = ProviderContainer(overrides: [
    fakeAuth(),
    devicesRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(container.dispose);
  await container.read(authControllerProvider.future);
  return container;
}

void main() {
  test('처음에는 발급된 코드가 없다', () async {
    final container = await _container(FakeDevicesRepository(issuedCode: _code));

    expect(container.read(pairingCodeControllerProvider).value, isNull);
  });

  test('issue는 발급된 코드를 상태로 둔다', () async {
    final repo = FakeDevicesRepository(issuedCode: _code);
    final container = await _container(repo);

    await container.read(pairingCodeControllerProvider.notifier).issue();

    expect(container.read(pairingCodeControllerProvider).value?.code, 'CODE-1');
    expect(repo.issueCalls, 1);
  });

  test('issue가 실패하면 오류 상태가 되고 ApiException 메시지를 보존한다', () async {
    final repo = FakeDevicesRepository(
      issueError: ApiException('요청이 너무 많아요.', statusCode: 429),
    );
    final container = await _container(repo);

    await container.read(pairingCodeControllerProvider.notifier).issue();

    final state = container.read(pairingCodeControllerProvider);
    expect(state.hasError, isTrue);
    expect((state.error as ApiException).statusCode, 429);
  });

  test('발급 중에 다시 issue를 호출해도 요청은 한 번만 나간다', () async {
    final repo = FakeDevicesRepository(issuedCode: _code);
    final container = await _container(repo);
    final controller = container.read(pairingCodeControllerProvider.notifier);

    await Future.wait([controller.issue(), controller.issue()]);

    expect(repo.issueCalls, 1);
  });

  test('사용자가 바뀌면(로그아웃) 이전 코드는 지워진다', () async {
    final repo = FakeDevicesRepository(issuedCode: _code);
    final container = await _container(repo);
    // 이 구독이 있어야 provider가 로그아웃 시점에 살아 있다.
    final sub = container.listen(pairingCodeControllerProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(pairingCodeControllerProvider.notifier).issue();
    expect(container.read(pairingCodeControllerProvider).value, isNotNull);

    await container.read(authControllerProvider.notifier).logout();
    await container.pump();

    expect(container.read(pairingCodeControllerProvider).value, isNull);
  });

  test('agentDevicesProvider는 저장소의 장치 목록을 돌려준다', () async {
    final repo = FakeDevicesRepository(devices: [deviceOf('d1', 'RIG-PC')]);
    final container = await _container(repo);

    final devices = await container.read(agentDevicesProvider.future);

    expect(devices.map((d) => d.name), ['RIG-PC']);
  });
}
