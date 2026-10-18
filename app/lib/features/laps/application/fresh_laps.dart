import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/fresh_highlight.dart';

/// 실시간으로 막 들어온 랩을 "새 랩"으로 기억하는 시간(D-50, docs/15 §9).
/// 강조가 사라지는 시간([kFreshHighlightDuration])보다 조금 길다 — 목록을 다시 불러오는 동안 늦게 그려진 행도 끝까지 사라지는 강조를 보이게.
const Duration kFreshLapKeepDuration = Duration(seconds: 5);

/// 막 들어온 랩 Id들(docs/15 §9 "잠깐 강조"). Laps 표·Dashboard 최근 랩이 이 Id의 행을 [FreshHighlight]로 칠한다.
class FreshLapIds extends Notifier<Set<String>> {
  final _timers = <String, Timer>{};

  @override
  Set<String> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return const {};
  }

  /// [lapId]를 새 랩으로 표시하고 [kFreshLapKeepDuration] 뒤에 지운다. 같은 랩이 다시 오면 시간을 새로 잰다.
  void mark(String lapId) {
    _timers.remove(lapId)?.cancel();
    state = {...state, lapId};
    _timers[lapId] = Timer(kFreshLapKeepDuration, () {
      _timers.remove(lapId);
      state = {
        for (final id in state)
          if (id != lapId) id,
      };
    });
  }
}

final freshLapIdsProvider = NotifierProvider<FreshLapIds, Set<String>>(FreshLapIds.new);
