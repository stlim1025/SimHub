import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/realtime/ranking_hub_client.dart';
import '../../../core/util/lap_time.dart';
import '../application/laps_providers.dart';
import '../domain/lap_models.dart';

/// 내 랩 기록. 개인 최고 + 랩 목록(무효/적격 배지, 섹터). LapRecorded/PersonalBest 수신 시 목록 갱신(05 §3).
class MyLapsPage extends ConsumerStatefulWidget {
  const MyLapsPage({super.key, this.trackId, this.trackName});

  final String? trackId;
  final String? trackName;

  @override
  ConsumerState<MyLapsPage> createState() => _MyLapsPageState();
}

class _MyLapsPageState extends ConsumerState<MyLapsPage> {
  final _subs = <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    // 개인 알림(user 그룹) 수신을 위해 Hub 연결 후 목록 갱신 트리거.
    final hub = ref.read(rankingHubClientProvider);
    unawaited(hub.connect());
    void refresh(_) {
      if (mounted) ref.invalidate(myLapsProvider(widget.trackId));
    }

    _subs.add(hub.lapRecorded.listen(refresh));
    _subs.add(hub.personalBest.listen(refresh));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myLaps = ref.watch(myLapsProvider(widget.trackId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/home')),
        title: Text(widget.trackName == null ? '내 기록' : '내 기록 · ${widget.trackName}'),
      ),
      body: myLaps.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e is ApiException ? e.message : '기록을 불러오지 못했어요.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(myLapsProvider(widget.trackId)),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(myLapsProvider(widget.trackId)),
          child: _LapsView(data: data),
        ),
      ),
    );
  }
}

class _LapsView extends StatelessWidget {
  const _LapsView({required this.data});

  final MyLaps data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (data.personalBest != null)
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.emoji_events),
              title: const Text('개인 최고'),
              trailing: Text(
                formatLapTime(data.personalBest!.lapTimeMs),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text('전체 ${data.total}랩', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (data.laps.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('아직 기록이 없어요.')))
        else
          ...data.laps.map((lap) => _LapCard(lap: lap)),
      ],
    );
  }
}

class _LapCard extends StatelessWidget {
  const _LapCard({required this.lap});

  final Lap lap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${lap.trackName} · ${lap.sessionType}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(formatLapTime(lap.lapTimeMs),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                if (!lap.isValid)
                  const Chip(label: Text('무효'), visualDensity: VisualDensity.compact),
                if (lap.isRankingEligible)
                  const Chip(label: Text('랭킹 적격'), visualDensity: VisualDensity.compact),
                for (final s in lap.sectors)
                  Chip(
                    label: Text('S${s.sectorNumber} ${formatLapTime(s.sectorTimeMs)}'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
