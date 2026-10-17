import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/core/time/clock_provider.dart';
import 'package:simcenter_app/features/devices/application/devices_providers.dart';
import 'package:simcenter_app/features/devices/data/devices_repository.dart';
import 'package:simcenter_app/features/devices/domain/device_models.dart';
import 'package:simcenter_app/features/devices/presentation/telemetry_app_page.dart';

import 'support/fakes.dart';

const _firstCode = 'K7F2-9QXM';
const _secondCode = 'ZZZZ-2222';
const _codeLifetime = Duration(minutes: 10);
final _tooManyRequests = ApiException('요청이 너무 많아요. 잠시 후 다시 시도해 주세요.', statusCode: 429);

/// 테스트가 시계를 직접 앞으로 돌릴 수 있는 환경. 발급되는 코드의 만료 시각은 발급 시점의 [now] 기준이다.
class _Env {
  _Env({List<AgentDevice> devices = const [], Object? issueError, Object? revokeError}) {
    repo = FakeDevicesRepository(
      devices: devices,
      issueError: issueError,
      revokeError: revokeError,
      issuedCode: (n) => PairingCode(
        code: n == 1 ? _firstCode : _secondCode,
        expiresAt: now.add(_codeLifetime),
      ),
    );
  }

  late final FakeDevicesRepository repo;
  DateTime now = DateTime.utc(2026, 10, 17, 12);
}

Widget _app(_Env env, {List<Override> extra = const []}) => ProviderScope(
      overrides: [
        fakeAuth(),
        devicesRepositoryProvider.overrideWithValue(env.repo),
        clockProvider.overrideWithValue(() => env.now),
        ...extra,
      ],
      child: const MaterialApp(home: Scaffold(body: TelemetryAppPage())),
    );

Future<_Env> _pumpPage(
  WidgetTester t, {
  List<AgentDevice> devices = const [],
  Object? issueError,
  Object? revokeError,
}) async {
  setViewSize(t, const Size(1000, 2600));
  final env = _Env(devices: devices, issueError: issueError, revokeError: revokeError);
  await t.pumpWidget(_app(env));
  await _settle(t);
  return env;
}

/// 코드가 표시되는 동안에는 1초 타이머가 계속 프레임을 만들어 pumpAndSettle이 끝나지 않는다.
/// 애니메이션(다이얼로그·스낵바)이 끝날 만큼만 시간을 흘린다.
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _issueCode(WidgetTester t, {String label = '연결 코드 발급'}) async {
  await t.tap(find.text(label));
  await _settle(t);
}

Finder _deviceRow(String id) => find.byKey(ValueKey('device-$id'));

Finder _inRow(String id, Finder matching) => find.descendant(of: _deviceRow(id), matching: matching);

Finder _inDialog(Finder matching) => find.descendant(of: find.byType(AlertDialog), matching: matching);

void main() {
  testWidgets('TelemetryAppPage_NoDevices_ShowsGuide', (t) async {
    setViewSize(t, const Size(1000, 2600));
    await t.pumpWidget(ProviderScope(
      overrides: [
        fakeAuth(),
        agentDevicesProvider.overrideWith((ref) async => const <AgentDevice>[]),
      ],
      child: const MaterialApp(home: Scaffold(body: TelemetryAppPage())),
    ));
    await t.pumpAndSettle();

    expect(find.text('연결된 PC가 없습니다'), findsOneWidget);
    expect(find.text('연결 코드 발급'), findsOneWidget);
    expect(find.text('설치 파일 준비 중'), findsOneWidget);
    expect(find.textContaining('dotnet run -- pair <코드>'), findsOneWidget);
  });

  testWidgets('F1 25 UDP 설정 안내(On · 2025 · 20777 · Agent PC IP)를 보여준다', (t) async {
    await _pumpPage(t);

    expect(find.text('UDP Telemetry'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('UDP Format'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('UDP Port'), findsOneWidget);
    expect(find.text('20777'), findsOneWidget);
    expect(find.text('UDP IP Address'), findsOneWidget);
    expect(find.textContaining('Agent PC IP'), findsOneWidget);
  });

  group('연결 코드 발급', () {
    testWidgets('발급하면 코드와 10:00 남은 시간이 보인다', (t) async {
      final env = await _pumpPage(t);
      expect(find.text(_firstCode), findsNothing);

      await _issueCode(t);

      expect(env.repo.issueCalls, 1);
      expect(find.text(_firstCode), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('연결 코드 발급'), findsNothing);
    });

    testWidgets('1초 타이머가 clockProvider 기준으로 남은 시간을 줄인다', (t) async {
      final env = await _pumpPage(t);
      await _issueCode(t);

      env.now = env.now.add(const Duration(minutes: 1, seconds: 1));
      await t.pump(const Duration(seconds: 1));

      expect(find.text('8:59'), findsOneWidget);
      expect(find.text('만료됨'), findsNothing);
    });

    testWidgets('만료되면 만료됨과 다시 발급 버튼을 보이고 복사는 숨긴다', (t) async {
      final env = await _pumpPage(t);
      await _issueCode(t);
      expect(find.text('복사'), findsOneWidget);

      env.now = env.now.add(_codeLifetime);
      await t.pump(const Duration(seconds: 1));

      expect(find.text('만료됨'), findsOneWidget);
      expect(find.text('다시 발급'), findsOneWidget);
      expect(find.text('복사'), findsNothing);
    });

    testWidgets('다시 발급하면 새 코드와 새 만료 시각이 보인다', (t) async {
      final env = await _pumpPage(t);
      await _issueCode(t);
      env.now = env.now.add(_codeLifetime + const Duration(seconds: 30));
      await t.pump(const Duration(seconds: 1));

      await _issueCode(t, label: '다시 발급');

      expect(env.repo.issueCalls, 2);
      expect(find.text(_secondCode), findsOneWidget);
      expect(find.text(_firstCode), findsNothing);
      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('만료됨'), findsNothing);
    });

    testWidgets('복사 버튼은 코드를 클립보드에 넣는다', (t) async {
      String? clipboardText;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _pumpPage(t);
      await _issueCode(t);

      await t.tap(find.text('복사'));
      await _settle(t);

      expect(clipboardText, _firstCode);
      expect(find.text('복사했어요'), findsOneWidget);
    });

    testWidgets('발급이 429로 거절되면 오류 문구를 보이고 다시 발급할 수 있다', (t) async {
      final env = await _pumpPage(t, issueError: _tooManyRequests);

      await _issueCode(t);

      expect(env.repo.issueCalls, 1);
      expect(find.text(_tooManyRequests.message), findsOneWidget);
      expect(find.text('연결 코드 발급'), findsOneWidget);
    });

    testWidgets('만료 후 다시 발급이 429로 실패하면 만료된 코드 대신 오류를 보인다', (t) async {
      final env = await _pumpPage(t);
      await _issueCode(t);
      env.now = env.now.add(_codeLifetime);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('만료됨'), findsOneWidget);
      env.repo.issueError = _tooManyRequests;

      await _issueCode(t, label: '다시 발급');

      expect(env.repo.issueCalls, 2);
      expect(find.text(_tooManyRequests.message), findsOneWidget);
      expect(find.text(_firstCode), findsNothing);
      expect(find.text('만료됨'), findsNothing);
      expect(find.text('연결 코드 발급'), findsOneWidget);
    });

    testWidgets('실패 뒤 다시 발급이 성공하면 오류가 사라지고 새 코드를 보인다', (t) async {
      final env = await _pumpPage(t);
      await _issueCode(t);
      env.now = env.now.add(_codeLifetime);
      await t.pump(const Duration(seconds: 1));
      env.repo.issueError = _tooManyRequests;
      await _issueCode(t, label: '다시 발급');
      env.repo.issueError = null;

      await _issueCode(t);

      expect(find.text(_tooManyRequests.message), findsNothing);
      expect(find.text(_secondCode), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
    });

    testWidgets('예상 밖 오류는 일반 안내 문구로 보인다', (t) async {
      await _pumpPage(t, issueError: StateError('boom'));

      await _issueCode(t);

      expect(find.text('연결 코드를 발급하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('연결 코드는 로그로 남기지 않는다', (t) async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      try {
        await _pumpPage(t);
        await _issueCode(t);
      } finally {
        // 테스트 프레임워크는 tearDown보다 먼저 debugPrint 원복 여부를 검사한다.
        debugPrint = original;
      }

      expect(find.text(_firstCode), findsOneWidget);
      expect(logs.where((l) => l.contains(_firstCode)), isEmpty);
    });

    testWidgets('화면을 닫으면 1초 타이머도 함께 정리된다', (t) async {
      final env = await _pumpPage(t);
      await _issueCode(t);

      await t.pumpWidget(const SizedBox.shrink());
      env.now = env.now.add(const Duration(seconds: 5));
      await t.pump(const Duration(seconds: 5));

      expect(t.takeException(), isNull);
    });
  });

  group('연결된 PC', () {
    final seenAt = DateTime.utc(2026, 10, 17, 11, 57);

    testWidgets('이름과 마지막 수신 시각을 보여주고 아직 없으면 안내한다', (t) async {
      await _pumpPage(t, devices: [
        deviceOf('d1', 'RIG-PC', lastSeenAt: seenAt),
        deviceOf('d2', 'LAPTOP'),
      ]);

      expect(find.text('RIG-PC'), findsOneWidget);
      expect(find.text('LAPTOP'), findsOneWidget);
      expect(_inRow('d1', find.text('마지막 수신 3분 전')), findsOneWidget);
      expect(_inRow('d2', find.text('마지막 수신 없음')), findsOneWidget);
      expect(find.text('연결 해제'), findsNWidgets(2));
    });

    testWidgets('장치가 없으면 목록 영역은 연결 방법만 안내한다', (t) async {
      await _pumpPage(t);

      expect(find.textContaining('연결 코드를 Agent에 입력하면'), findsOneWidget);
      expect(find.text('연결 해제'), findsNothing);
    });

    testWidgets('연결 해제는 확인 대화상자에서 취소하면 아무 일도 하지 않는다', (t) async {
      final env = await _pumpPage(t, devices: [deviceOf('d1', 'RIG-PC', lastSeenAt: seenAt)]);

      await t.tap(_inRow('d1', find.text('연결 해제')));
      await _settle(t);
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(_inDialog(find.text('취소')));
      await _settle(t);

      expect(find.byType(AlertDialog), findsNothing);
      expect(env.repo.revoked, isEmpty);
      expect(find.text('RIG-PC'), findsOneWidget);
    });

    testWidgets('확인하면 revoke를 호출하고 목록을 다시 불러온다', (t) async {
      final env = await _pumpPage(t, devices: [
        deviceOf('d1', 'RIG-PC', lastSeenAt: seenAt),
        deviceOf('d2', 'LAPTOP'),
      ]);
      final loadsBefore = env.repo.getDevicesCalls;

      await t.tap(_inRow('d1', find.text('연결 해제')));
      await _settle(t);
      await t.tap(_inDialog(find.text('연결 해제')));
      await _settle(t);

      expect(env.repo.revoked, ['d1']);
      expect(env.repo.getDevicesCalls, loadsBefore + 1);
      expect(find.text('RIG-PC'), findsNothing);
      expect(find.text('LAPTOP'), findsOneWidget);
    });

    testWidgets('해제에 실패하면 오류 문구를 보이고 목록은 그대로다', (t) async {
      final env = await _pumpPage(
        t,
        devices: [deviceOf('d1', 'RIG-PC', lastSeenAt: seenAt)],
        revokeError: ApiException('대상을 찾을 수 없어요.', statusCode: 404),
      );

      await t.tap(_inRow('d1', find.text('연결 해제')));
      await _settle(t);
      await t.tap(_inDialog(find.text('연결 해제')));
      await _settle(t);

      expect(env.repo.revoked, ['d1']);
      expect(find.text('대상을 찾을 수 없어요.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('새로고침 버튼은 목록을 다시 불러온다', (t) async {
      final env = await _pumpPage(t);
      final loadsBefore = env.repo.getDevicesCalls;

      await t.tap(find.byTooltip('새로고침'));
      await _settle(t);

      expect(env.repo.getDevicesCalls, loadsBefore + 1);
    });

    testWidgets('목록을 불러오지 못하면 오류와 다시 시도를 보인다', (t) async {
      setViewSize(t, const Size(1000, 2600));
      await t.pumpWidget(ProviderScope(
        overrides: [
          fakeAuth(),
          agentDevicesProvider.overrideWith((ref) async => throw ApiException('서버에 연결할 수 없어요.')),
        ],
        child: const MaterialApp(home: Scaffold(body: TelemetryAppPage())),
      ));
      await t.pumpAndSettle();

      expect(find.text('서버에 연결할 수 없어요.'), findsWidgets);
      expect(find.text('다시 시도'), findsWidgets);
    });
  });

  testWidgets('TelemetryAppPage_NarrowScreen_DoesNotOverflow', (t) async {
    setViewSize(t, const Size(375, 2800));
    final env = _Env(devices: [
      deviceOf('d1', 'A-VERY-LONG-DEVICE-NAME-FOR-THE-RIG-PC', lastSeenAt: DateTime.utc(2026, 7, 27, 12)),
    ]);
    await t.pumpWidget(_app(env));
    await _settle(t);
    await _issueCode(t);

    expect(t.takeException(), isNull);
    expect(find.text(_firstCode), findsOneWidget);
    expect(find.text('연결 해제'), findsOneWidget);
  });

  group('Connection Status', () {
    testWidgets('최근 5분 안에 받았으면 데이터 수신 중', (t) async {
      await _pumpPage(t, devices: [
        deviceOf('d1', 'RIG-PC', lastSeenAt: DateTime.utc(2026, 10, 17, 11, 56)),
      ]);

      expect(find.text('데이터 수신 중'), findsOneWidget);
    });

    testWidgets('오래전이면 마지막 수신 시점을 알려준다', (t) async {
      await _pumpPage(t, devices: [
        deviceOf('d1', 'RIG-PC', lastSeenAt: DateTime.utc(2026, 7, 27, 12)),
      ]);

      expect(find.text('최근 데이터 없음 · 마지막 수신 82일 전'), findsOneWidget);
    });

    testWidgets('받은 적이 없으면 아직 받은 데이터가 없습니다', (t) async {
      await _pumpPage(t, devices: [deviceOf('d1', 'RIG-PC')]);

      expect(find.text('아직 받은 데이터가 없습니다'), findsOneWidget);
    });
  });
}
