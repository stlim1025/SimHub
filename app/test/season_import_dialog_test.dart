import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/features/seasons/data/seasons_repository.dart';
import 'package:simcenter_app/features/seasons/domain/season_import_models.dart';
import 'package:simcenter_app/features/seasons/domain/season_models.dart';
import 'package:simcenter_app/features/seasons/presentation/season_import_dialog.dart';
import 'package:simcenter_app/features/seasons/presentation/seasons_page.dart';

import 'support/fakes.dart';

const _markdown = '# Season: Driver Career\n\n**Game**: F1 2025 | **Mode**: Driver Career';

SeasonImportPreview _preview({bool alreadyImported = false}) => SeasonImportPreview.fromJson({
      'title': 'Season 1',
      'gameCode': 'F1_25',
      'gameMode': 'DriverCareer',
      'teamName': 'Ferrari',
      'playerName': 'GOMDOL SUPER',
      'documents': [
        {'kind': 'InGameStandings', 'title': 'Season 1', 'rounds': 5, 'sessions': 5, 'drivers': 22},
        {'kind': 'F1LapsSession', 'title': 'Australia Race', 'rounds': 1, 'sessions': 1, 'drivers': 6},
      ],
      'rounds': [
        {
          'round': 1,
          'trackName': 'Melbourne',
          'myPoints': 25,
          'sessions': [
            {'sessionType': 'Race', 'sessionKind': 'Race', 'source': 'Imported', 'myPosition': 1, 'carCount': 22, 'lapCount': 6},
          ],
        },
        {
          'round': 6,
          'trackName': 'Miami',
          'myPoints': 0,
          'sessions': [
            {'sessionType': 'Qualifying', 'sessionKind': 'Qualifying1', 'source': 'Recorded', 'myPosition': 5, 'carCount': 22, 'lapCount': 0},
          ],
        },
      ],
      'drivers': [
        {'position': 1, 'name': 'Lando NORRIS', 'teamName': 'McLaren', 'teamColor': '#FF8000', 'points': 93, 'isPlayer': false},
        {'position': 3, 'name': 'GOMDOL SUPER', 'teamName': 'Ferrari', 'teamColor': '#E8002D', 'points': 75, 'isPlayer': true},
      ],
      'constructors': [
        {'position': 1, 'teamName': 'McLaren', 'teamColor': '#FF8000', 'points': 172},
      ],
      'linkCandidate': {
        'seasonLinkId': 2160041047,
        'sessions': [
          {'sessionId': 's1', 'kind': 'Qualifying1', 'trackName': 'Miami', 'classifiedAt': '2026-10-17T10:00:00Z'},
          {'sessionId': 's2', 'kind': 'Qualifying2', 'trackName': 'Miami', 'classifiedAt': '2026-10-17T10:30:00Z'},
          {'sessionId': 's3', 'kind': 'Qualifying3', 'trackName': 'Miami', 'classifiedAt': '2026-10-17T11:00:00Z'},
        ],
      },
      'alreadyImported': alreadyImported,
    });

Future<GoRouter> _pump(WidgetTester tester, SeasonsRepository repo) async {
  setViewSize(tester, const Size(1200, 2400));
  final router = GoRouter(initialLocation: '/seasons', routes: [
    GoRoute(path: '/seasons', builder: (_, _) => const Scaffold(body: SeasonsPage())),
    GoRoute(path: '/seasons/:seasonId', builder: (_, state) => Text('detail:${state.pathParameters['seasonId']}')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [seasonsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _openAndPaste(WidgetTester tester) async {
  await tester.tap(find.text(kSeasonImportTitle));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('season-import-markdown')), _markdown);
  await tester.pump();
}

FilledButton _importButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, kSeasonImportSubmitLabel));

void main() {
  test('SeasonSummary_ImportedFields_ParseAndModeLabelShowsTeam', () {
    final season = SeasonSummary.fromJson({
      'seasonId': 'se1',
      'gameCode': 'F1_25',
      'gameMode': 'DriverCareer',
      'firstSessionAt': '2026-10-01T09:00:00Z',
      'lastSessionAt': '2026-10-17T09:00:00Z',
      'roundCount': 6,
      'importedFrom': 'F1Laps',
      'myTeamName': 'Ferrari',
    });

    expect(season.importedFrom, 'F1Laps');
    expect(season.myTeamName, 'Ferrari');
  });

  group('SeasonImportDialog', () {
    testWidgets('Preview_ShowsDocumentsRoundsStandingsAndLink', (t) async {
      final repo = FakeSeasonsRepository()..importPreview = _preview();
      await _pump(t, repo);
      await _openAndPaste(t);

      expect(_importButton(t).onPressed, isNull);
      await t.tap(find.text(kSeasonImportPreviewLabel));
      await t.pumpAndSettle();

      expect(find.text('Season 1 · Driver Career · Ferrari · GOMDOL SUPER'), findsOneWidget);
      expect(find.text('인게임 순위표 · Season 1 — 라운드 5 · 세션 5 · 드라이버 22'), findsOneWidget);
      expect(find.text('연결할 게임 시즌: 2160041047, 옮길 세션 3개 (Miami Q1·Q2·Q3)'), findsOneWidget);
      expect(find.text('R1 Melbourne — R(22대, 6랩) · 내 점수 25'), findsOneWidget);
      expect(find.text('R6 Miami — Q1(기록, 22대) · 내 점수 0'), findsOneWidget);
      expect(find.text('1. Lando NORRIS · McLaren · 93점'), findsOneWidget);
      expect(find.text('3. GOMDOL SUPER · Ferrari · 75점'), findsOneWidget);
      expect(find.text('1. McLaren · 172점'), findsOneWidget);
      expect(_importButton(t).onPressed, isNotNull);
    });

    testWidgets('Import_ClosesAndNavigatesToSeason', (t) async {
      final repo = FakeSeasonsRepository()
        ..importPreview = _preview()
        ..importedSeasonId = 'new-season';
      final router = await _pump(t, repo);
      await _openAndPaste(t);
      await t.tap(find.text(kSeasonImportPreviewLabel));
      await t.pumpAndSettle();

      await t.tap(find.widgetWithText(FilledButton, kSeasonImportSubmitLabel));
      await t.pumpAndSettle();

      expect(repo.importRequests, ['preview', 'import']);
      expect(router.routeInformationProvider.value.uri.toString(), '/seasons/new-season');
      expect(find.text('detail:new-season'), findsOneWidget);
    });

    testWidgets('PreviewError_ShowsMessageInline', (t) async {
      final repo = FakeSeasonsRepository()..importError = ApiException('9번째 줄: Best Lap 형식이 아닙니다', statusCode: 400);
      await _pump(t, repo);
      await _openAndPaste(t);

      await t.tap(find.text(kSeasonImportPreviewLabel));
      await t.pumpAndSettle();

      expect(find.text('9번째 줄: Best Lap 형식이 아닙니다'), findsOneWidget);
      expect(find.byType(SeasonImportDialog), findsOneWidget);
      expect(_importButton(t).onPressed, isNull);
    });

    testWidgets('AlreadyImported_DisablesImport', (t) async {
      final repo = FakeSeasonsRepository()..importPreview = _preview(alreadyImported: true);
      await _pump(t, repo);
      await _openAndPaste(t);

      await t.tap(find.text(kSeasonImportPreviewLabel));
      await t.pumpAndSettle();

      expect(find.text(kSeasonImportAlreadyText), findsOneWidget);
      expect(_importButton(t).onPressed, isNull);
    });

    testWidgets('ImportConflict_StaysOpenWithMessage', (t) async {
      final repo = FakeSeasonsRepository()..importPreview = _preview();
      await _pump(t, repo);
      await _openAndPaste(t);
      await t.tap(find.text(kSeasonImportPreviewLabel));
      await t.pumpAndSettle();

      repo.importError = ApiException('이미 가져온 시즌입니다.', statusCode: 409);
      await t.tap(find.widgetWithText(FilledButton, kSeasonImportSubmitLabel));
      await t.pumpAndSettle();

      expect(find.text('이미 가져온 시즌입니다.'), findsOneWidget);
      expect(find.byType(SeasonImportDialog), findsOneWidget);
    });

    testWidgets('PhoneWidth_PreviewDoesNotOverflow', (t) async {
      final repo = FakeSeasonsRepository()..importPreview = _preview();
      await _pump(t, repo);
      setViewSize(t, const Size(375, 812));
      await t.pumpAndSettle();
      await _openAndPaste(t);

      await t.tap(find.text(kSeasonImportPreviewLabel));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('season-import-preview')), findsOneWidget);
    });

    testWidgets('EditingText_ClearsStalePreview', (t) async {
      final repo = FakeSeasonsRepository()..importPreview = _preview();
      await _pump(t, repo);
      await _openAndPaste(t);
      await t.tap(find.text(kSeasonImportPreviewLabel));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('season-import-preview')), findsOneWidget);

      await t.enterText(find.byKey(const Key('season-import-markdown')), '$_markdown\n');
      await t.pump();

      expect(find.byKey(const Key('season-import-preview')), findsNothing);
      expect(_importButton(t).onPressed, isNull);
    });
  });
}
