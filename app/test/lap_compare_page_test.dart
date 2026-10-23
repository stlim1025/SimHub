import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/theme/app_palette.dart';
import 'package:simcenter_app/core/theme/app_theme.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_compare.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';

import 'support/fakes.dart';
import 'support/lap_detail_harness.dart';

const _leaderboardName = '익명 드라이버';
const _mclaren = LapTeam(name: 'McLaren', color: '#FF8000');

/// 리더보드 최고 = 남의 랩 97.000초(익명), 랩 ID 비교 = 남의 공개 랩 99.000초, 그 밖 = 기본 표본.
LapDetail? _byCompare(String lapId, LapCompareSelection compare) => switch (compare.kind) {
      LapCompareKind.leaderboard => sampleDetail(
          comparison: comparisonOf('r1', 97000,
              kind: LapCompareKind.leaderboard, isMine: false, displayName: _leaderboardName, team: _mclaren, hasTrace: true),
        ),
      LapCompareKind.lap when compare.compareLapId == '0192f0aa-3333-7000-8000-000000000003' =>
        sampleDetail(withComparison: false, unavailable: ComparisonUnavailable.notFound),
      LapCompareKind.lap => sampleDetail(
          comparison: comparisonOf(compare.compareLapId!, 99000, kind: LapCompareKind.lap, isMine: false, displayName: '공개 라이벌'),
        ),
      LapCompareKind.none => sampleDetail(withComparison: false, unavailable: ComparisonUnavailable.noMatch),
      LapCompareKind.best => compare.filters.isEmpty ? sampleDetail() : sampleDetail(withComparison: false),
    };

FakeLapDetailRepository _repo({Map<String, LapTrace> traces = const {}}) =>
    FakeLapDetailRepository(details: {'l1': sampleDetail()}, traces: traces, compared: _byCompare);

Future<void> _openCompareMenu(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('compare-with-menu')));
  await t.pumpAndSettle();
}

Future<void> _tapText(WidgetTester t, String text) async {
  await t.tap(find.text(text).last);
  await t.pumpAndSettle();
}

void main() {
  group('Compare with', () {
    testWidgets('메뉴에 4가지가 있고, 리더보드를 고르면 주소·요청·표가 바뀐다', (t) async {
      final repo = _repo();
      final router = await pumpLapDetail(t, detailRepo: repo, location: '/laps/l1?tab=details');

      await _openCompareMenu(t);
      for (final label in [
        'Compare with: Your best lap',
        'Compare with: Leaderboard best lap',
        'Compare with: Another lap ID',
        "Don't compare lap",
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await _tapText(t, 'Compare with: Leaderboard best lap');

      expect(locationOf(router), '/laps/l1?tab=details&compare=leaderboard');
      expect(repo.compareRequests.last.kind, LapCompareKind.leaderboard);
      expect(find.text('Compare with: Leaderboard best lap'), findsOneWidget);
      expect(find.text('리더보드 랩'), findsOneWidget);
      expect(find.text('$_leaderboardName · McLaren'), findsOneWidget);
    });

    testWidgets('주소의 비교 선택으로 바로 열린다(새로고침·공유 유지)', (t) async {
      final repo = _repo();
      await pumpLapDetail(t, detailRepo: repo, location: '/laps/l1?compare=leaderboard&sameTeam=true');

      expect(repo.compareRequests.single,
          const LapCompareSelection(kind: LapCompareKind.leaderboard, filters: {LapCompareFilter.sameTeam}));
      expect(find.text('Compare with: Leaderboard best lap'), findsOneWidget);
      expect(find.text('Filter by (1)'), findsOneWidget);
    });

    testWidgets('Another lap ID는 창을 열고, 형식이 틀리면 알리고, 맞으면 그 랩과 비교한다', (t) async {
      final router = await pumpLapDetail(t, detailRepo: _repo());

      await _openCompareMenu(t);
      await _tapText(t, 'Compare with: Another lap ID');
      expect(find.text('비교할 랩 ID'), findsOneWidget);

      await t.enterText(find.byKey(const ValueKey('compare-lap-id-field')), 'nope');
      await _tapText(t, '비교');
      expect(find.text('랩 ID 형식이 아니에요'), findsOneWidget);

      await t.enterText(find.byKey(const ValueKey('compare-lap-id-field')), ' 0192f0aa-2222-7000-8000-000000000002 ');
      await _tapText(t, '비교');

      expect(locationOf(router), '/laps/l1?compare=lap&compareLapId=0192f0aa-2222-7000-8000-000000000002');
      expect(find.text('비교 랩'), findsOneWidget);
      expect(find.text('공개 라이벌'), findsOneWidget);
    });

    testWidgets('Another lap ID 창을 취소하면 선택이 그대로다', (t) async {
      final router = await pumpLapDetail(t, detailRepo: _repo());

      await _openCompareMenu(t);
      await _tapText(t, 'Compare with: Another lap ID');
      await _tapText(t, '취소');

      expect(locationOf(router), '/laps/l1');
    });

    testWidgets('비교할 수 없는 랩 ID(없거나 비공개)면 그 까닭을 보인다', (t) async {
      await pumpLapDetail(t, detailRepo: _repo(), location: '/laps/l1?compare=lap&compareLapId=0192f0aa-3333-7000-8000-000000000003');

      expect(find.text('비교할 수 없는 랩이에요(없거나 공개되지 않은 랩)'), findsOneWidget);
    });

    testWidgets("Don't compare면 Comparison 카드와 텔레메트리 비교(Delta·비교 트레이스)가 사라진다", (t) async {
      final repo = _repo(traces: {'l1': traceOf('l1', count: 20), 'best': traceOf('best', count: 20)});
      await pumpLapDetail(t, detailRepo: repo, location: '/laps/l1?compare=none');

      expect(find.text('Comparison'), findsNothing);
      expect(find.text("Don't compare lap"), findsOneWidget);

      await _tapText(t, 'Telemetry');
      expect(find.byKey(const ValueKey('telemetry-chart-delta')), findsNothing);
      expect(find.byKey(const ValueKey('legend-reference-lap')), findsNothing);
      expect(repo.comparisonTraceRequests, isEmpty);
    });

    testWidgets('리더보드 비교의 텔레메트리는 비교 트레이스 경로로 남의 랩을 읽고 범례에 이름을 보인다', (t) async {
      final repo = _repo(traces: {'l1': traceOf('l1', count: 20), 'r1': traceOf('r1', count: 20)});
      await pumpLapDetail(t, detailRepo: repo, location: '/laps/l1?tab=telemetry&compare=leaderboard');

      expect(repo.comparisonTraceRequests, ['r1']);
      expect(find.byKey(const ValueKey('telemetry-chart-delta')), findsOneWidget);
      expect(find.text('리더보드 랩 · $_leaderboardName 1:37.000'), findsOneWidget);
    });
  });

  group('Filter by', () {
    testWidgets('여러 개를 켜고 끌 수 있고, 탭과 비교 종류를 지킨다', (t) async {
      final router = await pumpLapDetail(t, detailRepo: _repo(), location: '/laps/l1?tab=telemetry&compare=leaderboard');

      await t.tap(find.byKey(const ValueKey('compare-filter-menu')));
      await t.pumpAndSettle();
      await _tapText(t, 'Same team');
      expect(locationOf(router), '/laps/l1?tab=telemetry&compare=leaderboard&sameTeam=true');

      await t.tap(find.byKey(const ValueKey('compare-filter-menu')));
      await t.pumpAndSettle();
      await _tapText(t, 'Same assists');
      expect(locationOf(router), '/laps/l1?tab=telemetry&compare=leaderboard&sameTeam=true&sameAssists=true');
      expect(find.text('Filter by (2)'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('compare-filter-menu')));
      await t.pumpAndSettle();
      await _tapText(t, 'Same team');
      expect(locationOf(router), '/laps/l1?tab=telemetry&compare=leaderboard&sameAssists=true');
    });

    testWidgets('필터에 맞는 랩이 없으면 그렇게 알린다', (t) async {
      await pumpLapDetail(t, detailRepo: _repo(), location: '/laps/l1?sameSessionType=true');

      expect(find.text('필터에 맞는 비교 랩이 없어요'), findsOneWidget);
    });

    testWidgets('랩 ID 비교·비교 안 함에서는 필터 메뉴를 쓸 수 없다', (t) async {
      for (final location in ['/laps/l1?compare=none', '/laps/l1?compare=lap&compareLapId=0192f0aa-2222-7000-8000-000000000002']) {
        await pumpLapDetail(t, detailRepo: _repo(), location: location);

        final menu = t.widget<PopupMenuButton<LapCompareFilter>>(find.byKey(const ValueKey('compare-filter-menu')));
        expect(menu.enabled, isFalse, reason: location);
      }
    });
  });

  group('Comparison 표', () {
    testWidgets('Delta 아래 줄에 비율(%)을 보인다', (t) async {
      await pumpLapDetail(t, detailRepo: _repo());

      final row = find.byKey(const ValueKey('comparison-percent-row'));
      // 98.448 vs 98.000 → +0.5%, S1 31.000 vs 30.500 → +1.6%, S3 34.000 vs 34.200 → -0.6%.
      for (final text in ['+0.5%', '+1.6%', '+0.4%', '-0.6%']) {
        expect(find.descendant(of: row, matching: find.text(text)), findsOneWidget, reason: text);
      }
      final context = t.element(row);
      expect(t.widget<Text>(find.descendant(of: row, matching: find.text('-0.6%'))).style?.color, context.palette.success);
    });

    testWidgets('리더보드 최고가 곧 이 랩이면 그렇게 알린다', (t) async {
      final repo = FakeLapDetailRepository(
        compared: (_, _) => sampleDetail(comparison: comparisonOf('l1', 98448, kind: LapCompareKind.leaderboard)),
      );
      await pumpLapDetail(t, detailRepo: repo, location: '/laps/l1?compare=leaderboard');

      expect(find.text('이 랩이 리더보드 최고 기록'), findsOneWidget);
    });
  });

  group('머리줄 · Share', () {
    testWidgets('머리줄은 "{트랙} Lap {랩타임}"이고 Share는 로그인 없이 보는 공유 주소(Telemetry 탭 + 비교 중인 랩 ID)를 복사한다', (t) async {
      String? clipboardText;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpLapDetail(
        t,
        detailRepo: _repo(),
        location: '/laps/l1?tab=telemetry&compare=leaderboard',
        shareBase: Uri.parse('https://simcenter.test/#/laps/l1'),
      );

      expect(find.text('Jeddah Lap 1:38.448'), findsOneWidget);
      await _tapText(t, 'Share');

      expect(clipboardText, 'https://simcenter.test/#/share/laps/l1?tab=telemetry&compareLapId=r1');
      expect(find.text('주소를 복사했어요'), findsOneWidget);
    });

    testWidgets('Your Best Laps 탭에서 누른 Share는 탭 없이 비교 중인 랩만 싣는다', (t) async {
      String? clipboardText;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpLapDetail(
        t,
        detailRepo: _repo(),
        location: '/laps/l1?tab=best',
        shareBase: Uri.parse('https://stlim1025.github.io/SimHub/#/laps/l1?tab=best'),
      );

      await _tapText(t, 'Share');

      expect(clipboardText, 'https://stlim1025.github.io/SimHub/#/share/laps/l1?compareLapId=best');
    });

    Future<String?> shareFrom(WidgetTester t, String location, {FakeLapDetailRepository? repo}) async {
      String? clipboardText;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpLapDetail(t, detailRepo: repo ?? _repo(), location: location, shareBase: Uri.parse('https://simcenter.test/'));
      await _tapText(t, 'Share');
      return clipboardText;
    }

    testWidgets('비교 안 함이면 Share 주소에 비교 랩이 없다', (t) async {
      expect(await shareFrom(t, '/laps/l1?tab=telemetry&compare=none'), 'https://simcenter.test/share/laps/l1?tab=telemetry');
    });

    testWidgets('맞는 비교 대상이 없으면 Share 주소에 비교 랩이 없다', (t) async {
      expect(await shareFrom(t, '/laps/l1?sameTeam=true'), 'https://simcenter.test/share/laps/l1');
    });

    testWidgets('비교 대상이 이 랩 자신이면 Share 주소에 비교 랩이 없다', (t) async {
      final repo = FakeLapDetailRepository(details: {'l1': sampleDetail(comparison: comparisonOf('l1', 98448))});
      expect(await shareFrom(t, '/laps/l1', repo: repo), 'https://simcenter.test/share/laps/l1');
    });
  });

  group('Driver Assists', () {
    testWidgets('6칸을 보이고 켜진 보조는 강조, Off·Manual은 흐리게', (t) async {
      await pumpLapDetail(t, detailRepo: _repo());

      expect(find.text('Driver Assists'), findsOneWidget);
      for (final label in ['Traction Control', 'Anti-Lock Brakes', 'Steering Assist', 'Braking Assist', 'Gearbox', 'Racing Line']) {
        expect(find.byKey(ValueKey('assist-$label')), findsOneWidget, reason: label);
      }
      Text valueOf(String label, String value) =>
          t.widget<Text>(find.descendant(of: find.byKey(ValueKey('assist-$label')), matching: find.text(value)));
      final palette = t.element(find.text('Driver Assists')).palette;
      expect(valueOf('Anti-Lock Brakes', 'On').style?.color, palette.link);
      expect(valueOf('Racing Line', 'Corners').style?.color, palette.link);
      expect(valueOf('Steering Assist', 'Off').style?.fontWeight, isNot(FontWeight.bold));
      expect(valueOf('Gearbox', 'Manual').style?.fontWeight, isNot(FontWeight.bold));
    });

    testWidgets('어시스트를 모르면 영역을 숨기고, 모르는 칸은 뺀다', (t) async {
      await pumpLapDetail(t, detailRepo: FakeLapDetailRepository(details: {'l1': sampleDetail(assists: null)}));
      expect(find.text('Driver Assists'), findsNothing);

      await pumpLapDetail(
        t,
        detailRepo: FakeLapDetailRepository(details: {'l1': sampleDetail(assists: const LapAssists(gearbox: 'Automatic'))}),
      );
      expect(find.text('Driver Assists'), findsOneWidget);
      expect(find.byKey(const ValueKey('assist-Gearbox')), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      expect(find.byKey(const ValueKey('assist-Traction Control')), findsNothing);
    });
  });

  testWidgets('375px에서 비교 메뉴·남의 랩 비교·어시스트가 두 테마 모두 넘치지 않는다', (t) async {
    final longName = FakeLapDetailRepository(
      compared: (_, _) => sampleDetail(
        comparison: comparisonOf('r1', 97000,
            kind: LapCompareKind.leaderboard,
            isMine: false,
            displayName: '아주아주아주 긴 이름을 가진 리더보드 드라이버',
            team: _mclaren),
      ),
    );
    for (final theme in [AppTheme.dark, AppTheme.light]) {
      await pumpLapDetail(
        t,
        detailRepo: longName,
        location: '/laps/l1?compare=leaderboard&sameTeam=true&sameAssists=true&sameSessionType=true',
        size: const Size(375, 5000),
        theme: theme,
      );

      expect(t.takeException(), isNull, reason: '${theme.brightness}');
    }
  });
}
