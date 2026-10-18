import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/profile/domain/avatar_teams.dart';

/// 프로필 사진 팀 코드 계약(docs/14 §4): 앱 [kAvatarTeams]가 OpenAPI `AvatarTeamCode` enum과 같은 순서·값인지 확인한다.
/// 백엔드 `AvatarTeamCodes`는 백엔드 테스트(`AvatarTeamCodeContractTests`)가 같은 enum과 비교한다 — 두 테스트가 세 목록을 묶는다.
const _contractRelativePath = 'shared/openapi/openapi.yaml';
const _schemaHeader = '    AvatarTeamCode:';
const _enumPrefix = 'enum: [';

/// 실행 폴더(app/)에서 위로 올라가며 저장소의 계약 파일을 찾는다.
File _findContract() {
  var dir = Directory.current.absolute;
  while (true) {
    final candidate = File('${dir.path}${Platform.pathSeparator}$_contractRelativePath');
    if (candidate.existsSync()) {
      return candidate;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('저장소에서 $_contractRelativePath를 찾지 못했습니다.');
    }
    dir = parent;
  }
}

/// `AvatarTeamCode` 스키마 블록 안의 `enum: [A, B]` 항목.
List<String> _schemaEnum(List<String> lines) {
  final start = lines.indexOf(_schemaHeader);
  expect(start, greaterThanOrEqualTo(0), reason: 'AvatarTeamCode 스키마가 없습니다.');
  for (final line in lines.skip(start + 1).takeWhile((l) => l.isEmpty || l.startsWith('      '))) {
    final trimmed = line.trim();
    if (trimmed.startsWith(_enumPrefix) && trimmed.endsWith(']')) {
      return [
        for (final item in trimmed.substring(_enumPrefix.length, trimmed.length - 1).split(','))
          if (item.trim().isNotEmpty) item.trim(),
      ];
    }
  }
  fail('AvatarTeamCode 스키마에 enum이 없습니다.');
}

void main() {
  test('앱 팀 코드 목록은 OpenAPI AvatarTeamCode enum과 같다', () {
    final lines = _findContract().readAsLinesSync();

    expect([for (final team in kAvatarTeams) team.code], _schemaEnum(lines));
  });
}
