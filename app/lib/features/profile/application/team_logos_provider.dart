import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/assets/asset_bundle_provider.dart';

/// 팀 로고 이미지 폴더(D-48, docs/15 §2.4). 파일 이름 = 팀 코드(`FER.png`), 저장소에는 넣지 않는다(상표).
const String kTeamLogoDirectory = 'assets/team_logos/';
const String _logoExtension = '.png';

/// 자산 목록 → 로고가 있는 팀 코드(대문자) → 자산 경로. [kTeamLogoDirectory] 바로 아래의 PNG만 쓴다
/// (폴더 안내 `README.md`·하위 폴더·다른 폴더는 뺀다). 순수 함수.
Map<String, String> teamLogoPathsFrom(Iterable<String> assets) => {
      for (final asset in assets)
        if (_isTeamLogo(asset))
          asset.substring(kTeamLogoDirectory.length, asset.length - _logoExtension.length).toUpperCase(): asset,
    };

bool _isTeamLogo(String asset) {
  if (!asset.startsWith(kTeamLogoDirectory) || !asset.toLowerCase().endsWith(_logoExtension)) {
    return false;
  }
  final name = asset.substring(kTeamLogoDirectory.length);
  return !name.contains('/') && name.length > _logoExtension.length;
}

/// 로고가 있는 팀 코드 → 자산 경로. 앱이 시작한 뒤 AssetManifest를 한 번 읽는다 — 없는 파일을 요청해 404를 내지 않는다.
/// 목록을 읽지 못하면 로고 없음(빈 맵)으로 보고 팀 색 원 + 코드를 그린다.
final teamLogoPathsProvider = FutureProvider<Map<String, String>>((ref) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(ref.watch(assetBundleProvider));
    return teamLogoPathsFrom(manifest.listAssets());
  } catch (e) {
    debugPrint('팀 로고 목록을 읽지 못했어요(코드 원으로 표시): $e');
    return const {};
  }
});
