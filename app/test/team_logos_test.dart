import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/profile/application/team_logos_provider.dart';
import 'package:simcenter_app/features/profile/presentation/avatar_picker.dart';
import 'package:simcenter_app/features/profile/presentation/team_avatar.dart';

Future<void> _pumpAvatar(WidgetTester tester, {String? teamCode = 'FER', List<Override> overrides = const []}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(body: Center(child: TeamAvatar(teamCode: teamCode, displayName: '홍길동', size: 52))),
    ),
  ));
  await tester.pumpAndSettle();
}

/// 테스트 서버의 로고 URL(실제로 읽지 않는다 — 테스트 환경의 HTTP는 모두 실패한다).
String? _testLogoUrl(String code) => teamLogoUrlFor('https://api.test', code);

void main() {
  group('teamLogoUrlFor (D-48)', () {
    test('API 오리진 + /team-logos/{코드 대문자}.png', () {
      expect(teamLogoUrlFor('https://api.example:8443', 'fer'), 'https://api.example:8443/team-logos/FER.png');
      expect(teamLogoUrlFor('https://api.example', 'RB'), 'https://api.example/team-logos/RB.png');
    });
  });

  group('TeamAvatar', () {
    testWidgets('고른 팀이면 서버 로고 URL로 이미지를 요청한다', (t) async {
      await _pumpAvatar(t, overrides: [teamLogoUrlProvider.overrideWithValue(_testLogoUrl)]);

      final image = t.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url, 'https://api.test/team-logos/FER.png');
    });

    testWidgets('로고를 읽지 못하면(없는 파일·네트워크 오류) 팀 코드로 대신한다', (t) async {
      await _pumpAvatar(t, overrides: [teamLogoUrlProvider.overrideWithValue(_testLogoUrl)]);

      // 테스트 환경의 HTTP 요청은 실패한다 → errorBuilder.
      expect(find.text('FER'), findsOneWidget);
    });

    testWidgets('로고 URL이 없으면 이미지를 요청하지 않고 팀 색 원 + 코드', (t) async {
      await _pumpAvatar(t, overrides: [teamLogoUrlProvider.overrideWithValue((_) => null)]);

      expect(find.byType(Image), findsNothing);
      expect(find.text('FER'), findsOneWidget);
    });

    testWidgets('팀을 고르지 않았으면 로고 없이 이름 첫 글자', (t) async {
      await _pumpAvatar(t, teamCode: null, overrides: [teamLogoUrlProvider.overrideWithValue(_testLogoUrl)]);

      expect(find.byType(Image), findsNothing);
      expect(find.text('홍'), findsOneWidget);
    });

    testWidgets('사진 고르기도 팀마다 서버 로고를 요청한다', (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [teamLogoUrlProvider.overrideWithValue(_testLogoUrl)],
        child: MaterialApp(
          home: Scaffold(body: AvatarPicker(selected: null, displayName: '홍길동', onSelected: (_) {})),
        ),
      ));
      await t.pumpAndSettle();

      final urls = t.widgetList<Image>(find.byType(Image)).map((i) => (i.image as NetworkImage).url).toList();
      expect(urls, contains('https://api.test/team-logos/RB.png'));
      expect(find.text('MER'), findsOneWidget); // 읽지 못한 로고는 코드로 보인다.
    });
  });
}
