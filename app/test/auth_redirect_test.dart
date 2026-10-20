import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/router/auth_redirect.dart';

/// 인증 리다이렉트가 원래 주소(공유 링크·새로고침)를 `from`으로 지켜 돌아오게 하는지.
void main() {
  Uri u(String s) => Uri.parse(s);

  test('세션 복원 중이면 원래 주소를 from에 담아 스플래시로 보낸다', () {
    expect(
      resolveAuthRedirect(loading: true, loggedIn: false, uri: u('/laps/l1?tab=telemetry&compare=leaderboard')),
      '/splash?from=%2Flaps%2Fl1%3Ftab%3Dtelemetry%26compare%3Dleaderboard',
    );
  });

  test('스플래시에 머무는 중에는 그대로 둔다', () {
    expect(resolveAuthRedirect(loading: true, loggedIn: false, uri: u('/splash?from=%2Flaps%2Fl1')), isNull);
  });

  test('복원이 끝나 로그인 상태면 from 주소로 돌아간다', () {
    expect(
      resolveAuthRedirect(loading: false, loggedIn: true, uri: u('/splash?from=%2Flaps%2Fl1%3Ftab%3Dtelemetry')),
      '/laps/l1?tab=telemetry',
    );
  });

  test('from이 없거나 인증 화면·외부 주소면 Dashboard로 간다', () {
    expect(resolveAuthRedirect(loading: false, loggedIn: true, uri: u('/splash')), '/');
    expect(resolveAuthRedirect(loading: false, loggedIn: true, uri: u('/login?from=%2Flogin')), '/');
    expect(resolveAuthRedirect(loading: false, loggedIn: true, uri: u('/splash?from=https%3A%2F%2Fevil.example')), '/');
    expect(resolveAuthRedirect(loading: false, loggedIn: true, uri: u('/splash?from=%2F%2Fevil.example')), '/');
  });

  test('로그아웃 상태면 from을 이어 받아 로그인으로 보낸다', () {
    expect(
      resolveAuthRedirect(loading: false, loggedIn: false, uri: u('/splash?from=%2Flaps%2Fl1')),
      '/login?from=%2Flaps%2Fl1',
    );
    expect(resolveAuthRedirect(loading: false, loggedIn: false, uri: u('/laps/l1')), '/login?from=%2Flaps%2Fl1');
    expect(resolveAuthRedirect(loading: false, loggedIn: false, uri: u('/')), '/login');
    expect(resolveAuthRedirect(loading: false, loggedIn: false, uri: u('/login?from=%2Flaps%2Fl1')), isNull);
  });

  test('로그인 상태의 /home·인증 화면은 Dashboard, 그 밖은 그대로', () {
    expect(resolveAuthRedirect(loading: false, loggedIn: true, uri: u('/home')), '/');
    expect(resolveAuthRedirect(loading: false, loggedIn: true, uri: u('/laps/l1')), isNull);
  });

  test('공유 링크(/share/**)는 복원 중·로그아웃·로그인 모두 리다이렉트하지 않는다', () {
    for (final loading in [true, false]) {
      for (final loggedIn in [true, false]) {
        expect(
          resolveAuthRedirect(loading: loading, loggedIn: loggedIn, uri: u('/share/laps/l1?tab=telemetry')),
          isNull,
          reason: 'loading=$loading loggedIn=$loggedIn',
        );
      }
    }
    expect(isSharePath('/share/laps/l1'), isTrue);
    expect(isSharePath('/shared'), isFalse);
  });
}
