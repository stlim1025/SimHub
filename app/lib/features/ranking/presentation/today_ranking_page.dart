import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/util/lap_time.dart';
import '../application/ranking_providers.dart';
import '../domain/ranking_models.dart';

/// 트랙별 실시간 TOP10(월별 기본, D-8a). RankingHub RankingUpdated 수신 시 자동 반영.
class TodayRankingPage extends ConsumerWidget {
  const TodayRankingPage({super.key, required this.trackId, required this.trackName});

  final String trackId;
  final String trackName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranking = ref.watch(rankingControllerProvider(trackId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/home')),
        title: Text(trackName),
        actions: [
          IconButton(
            tooltip: '이 트랙 내 기록',
            icon: const Icon(Icons.timer_outlined),
            onPressed: () => context.go(
              '/my-laps?trackId=$trackId&trackName=${Uri.encodeComponent(trackName)}',
            ),
          ),
        ],
      ),
      body: ranking.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e is ApiException ? e.message : '랭킹을 불러오지 못했어요.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(rankingControllerProvider(trackId)),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
        data: (snapshot) => _RankingList(snapshot: snapshot),
      ),
    );
  }
}

class _RankingList extends StatelessWidget {
  const _RankingList({required this.snapshot});

  final RankingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.entries.isEmpty) {
      return const Center(child: Text('아직 기록이 없어요. 첫 랩의 주인공이 되어보세요!'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Chip(label: Text('월별 · ${snapshot.periodKey}')),
              const Spacer(),
              const Icon(Icons.circle, size: 10, color: Colors.green),
              const SizedBox(width: 4),
              const Text('실시간'),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: snapshot.entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final e = snapshot.entries[i];
              return ListTile(
                leading: CircleAvatar(child: Text('${e.rank}')),
                title: Text(e.displayName),
                trailing: Text(
                  formatLapTime(e.bestLapTimeMs),
                  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
