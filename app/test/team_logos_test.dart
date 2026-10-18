import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/assets/asset_bundle_provider.dart';
import 'package:simcenter_app/features/profile/application/team_logos_provider.dart';
import 'package:simcenter_app/features/profile/presentation/avatar_picker.dart';
import 'package:simcenter_app/features/profile/presentation/team_avatar.dart';

/// `AssetManifest.bin`만 돌려주는 자산 묶음(실제 로고 파일은 없다).
class _ManifestBundle extends CachingAssetBundle {
  _ManifestBundle(this.assets);

  final List<String> assets;
  int manifestLoads = 0;

  @override
  Future<ByteData> load(String key) async {
    if (key != 'AssetManifest.bin') {
      throw FlutterError('없는 자산: $key');
    }
    manifestLoads++;
    return const StandardMessageCodec().encodeMessage({
      for (final asset in assets)
        asset: [
          {'asset': asset},
        ],
    })!;
  }
}

Future<void> _pumpAvatar(WidgetTester tester, {String? teamCode = 'FER', List<Override> overrides = const []}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(body: Center(child: TeamAvatar(teamCode: teamCode, displayName: '홍길동', size: 52))),
    ),
  ));
  await tester.pumpAndSettle();
}

Image? _logoImage(WidgetTester tester) {
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  return images.isEmpty ? null : images.single;
}

void main() {
  group('teamLogoPathsFrom (D-48)', () {
    test('assets/team_logos/ 바로 아래의 PNG만 코드(대문자) → 경로로 모은다', () {
      final paths = teamLogoPathsFrom(const [
        'assets/team_logos/FER.png',
        'assets/team_logos/mer.png',
        'assets/team_logos/README.md',
        'assets/team_logos/.gitignore',
        'assets/team_logos/sub/RB.png',
        'assets/other/HAA.png',
        'packages/country_flags/res/si/fr.si',
      ]);

      expect(paths, {
        'FER': 'assets/team_logos/FER.png',
        'MER': 'assets/team_logos/mer.png',
      });
    });

    test('README만 있으면(저장소 기본 상태) 로고가 없다', () {
      expect(teamLogoPathsFrom(const ['assets/team_logos/README.md']), isEmpty);
    });
  });

  group('teamLogoPathsProvider', () {
    test('자산 목록(AssetManifest)을 한 번 읽어 로고 경로를 만든다', () async {
      final bundle = _ManifestBundle(['assets/team_logos/FER.png', 'assets/team_logos/README.md']);
      final container = ProviderContainer(overrides: [assetBundleProvider.overrideWithValue(bundle)]);
      addTearDown(container.dispose);

      final first = await container.read(teamLogoPathsProvider.future);
      final second = await container.read(teamLogoPathsProvider.future);

      expect(first, {'FER': 'assets/team_logos/FER.png'});
      expect(second, same(first));
      expect(bundle.manifestLoads, 1);
    });

    test('자산 목록을 읽지 못하면 로고 없음으로 본다', () async {
      final failing = ProviderContainer(overrides: [assetBundleProvider.overrideWithValue(_FailingBundle())]);
      addTearDown(failing.dispose);

      expect(await failing.read(teamLogoPathsProvider.future), isEmpty);
    });
  });

  group('TeamAvatar', () {
    testWidgets('로고 파일이 있으면 팀 색 원 안에 로고 이미지를 그린다', (t) async {
      await _pumpAvatar(t, overrides: [
        teamLogoPathsProvider.overrideWith((ref) async => const {'FER': 'assets/team_logos/FER.png'}),
      ]);

      final image = _logoImage(t);
      expect(image, isNotNull);
      expect((image!.image as AssetImage).assetName, 'assets/team_logos/FER.png');
    });

    testWidgets('로고 파일이 없으면 지금처럼 팀 색 원 + 코드(이미지 요청 없음)', (t) async {
      await _pumpAvatar(t, overrides: [teamLogoPathsProvider.overrideWith((ref) async => const {'MER': 'x.png'})]);

      expect(_logoImage(t), isNull);
      expect(find.text('FER'), findsOneWidget);
    });

    testWidgets('로고 파일을 불러오지 못하면 코드로 대신한다', (t) async {
      await _pumpAvatar(t, overrides: [
        teamLogoPathsProvider.overrideWith((ref) async => const {'FER': 'assets/team_logos/FER.png'}),
      ]);

      expect(find.text('FER'), findsOneWidget); // 테스트 자산 묶음에는 FER.png가 없다 → errorBuilder.
    });

    testWidgets('저장소 기본 자산(README만)으로는 로고가 없다', (t) async {
      await _pumpAvatar(t);

      expect(_logoImage(t), isNull);
      expect(find.text('FER'), findsOneWidget);
    });

    testWidgets('사진 고르기도 로고가 있는 팀은 로고로 보인다', (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [teamLogoPathsProvider.overrideWith((ref) async => const {'RB': 'assets/team_logos/RB.png'})],
        child: MaterialApp(
          home: Scaffold(body: AvatarPicker(selected: null, displayName: '홍길동', onSelected: (_) {})),
        ),
      ));
      await t.pumpAndSettle();

      final images = t.widgetList<Image>(find.byType(Image)).toList();
      expect(images, hasLength(1));
      expect((images.single.image as AssetImage).assetName, 'assets/team_logos/RB.png');
      expect(find.text('MER'), findsOneWidget);
    });
  });
}

/// 자산 목록을 읽으면 실패하는 자산 묶음.
class _FailingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('자산 묶음 오류');
}
