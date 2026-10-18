import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/ranking_hub_client.dart';
import 'auth_controller.dart';

/// 허브 연결을 먼저 끊고 로그아웃한다(사이드바 로그아웃 아이콘·설정 화면 로그아웃 버튼 공통).
/// 허브 종료가 실패해도 로그아웃은 반드시 수행한다. 허브 종료를 기다리는 동안 호출한 위젯이 트리에서 사라져도
/// (화면 폭 변경 등) 끝까지 수행되도록, `ref.read`는 첫 `await` 전에 모두 끝낸다.
Future<void> signOut(WidgetRef ref) async {
  final hub = ref.read(rankingHubClientProvider);
  final auth = ref.read(authControllerProvider.notifier);
  try {
    await hub.stop();
  } catch (e) {
    debugPrint('랭킹 허브 종료 실패(로그아웃은 계속 진행): $e');
  }
  await auth.logout();
}
