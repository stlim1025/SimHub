import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/selected_game_provider.dart';
import '../data/setups_repository.dart';
import '../domain/setup_models.dart';

/// 셋업 목록 조회 조건(트랙 + `Dry`·`Wet` + 세션 종류). 레코드라 값 동등성으로 family 키가 된다.
typedef SetupListQuery = ({String trackId, String condition, String session});

/// 선택한 게임(계정 설정)의 트랙 목록. Setups·Tracks 목록 화면이 같이 쓴다.
final setupTracksProvider = FutureProvider.autoDispose<List<SetupTrackSummary>>(
  (ref) => ref.watch(setupsRepositoryProvider).getTracks(gameCode: ref.watch(selectedGameProvider)),
);

/// 한 트랙·조건의 상위 셋업 목록.
final setupListProvider = FutureProvider.autoDispose.family<SetupList, SetupListQuery>(
  (ref, query) => ref
      .watch(setupsRepositoryProvider)
      .getSetups(trackId: query.trackId, condition: query.condition, session: query.session),
);

/// 셋업 하나.
final setupDetailProvider = FutureProvider.autoDispose.family<SetupDetail, String>(
  (ref, setupId) => ref.watch(setupsRepositoryProvider).getSetup(setupId),
);
