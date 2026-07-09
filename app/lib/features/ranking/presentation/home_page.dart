import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/realtime/ranking_hub_client.dart';
import '../../auth/application/auth_controller.dart';
import '../../session/application/session_controller.dart';
import '../application/ranking_providers.dart';
import '../domain/ranking_models.dart';

/// 홈: 프로필 + 좌석 체크인 + 트랙 선택(→ 실시간 랭킹).
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _rigCode = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _rigCode.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(rankingHubClientProvider).stop();
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final session = ref.watch(sessionControllerProvider);
    final tracks = ref.watch(tracksProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('안녕하세요, ${user?.displayName ?? '드라이버'}님'),
        actions: [
          IconButton(
            tooltip: '내 기록',
            icon: const Icon(Icons.timer_outlined),
            onPressed: () => context.go('/my-laps'),
          ),
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: _busy ? null : _logout,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CheckInCard(
            session: session,
            rigController: _rigCode,
            busy: _busy,
            onCheckIn: () => _guard(() =>
                ref.read(sessionControllerProvider.notifier).checkIn(
                      _rigCode.text.trim(),
                      AppConfig.defaultGameCode,
                    )),
            onCheckOut: () => _guard(() => ref.read(sessionControllerProvider.notifier).checkOut()),
          ),
          const SizedBox(height: 24),
          Text('트랙', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          tracks.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _ErrorLine(
              message: e is ApiException ? e.message : '트랙을 불러오지 못했어요.',
              onRetry: () => ref.invalidate(tracksProvider),
            ),
            data: (items) => Column(
              children: items.map((t) => _TrackTile(track: t)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckInCard extends StatelessWidget {
  const _CheckInCard({
    required this.session,
    required this.rigController,
    required this.busy,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  final AsyncValue session;
  final TextEditingController rigController;
  final bool busy;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: session.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
          error: (e, _) => Text(e is ApiException ? e.message : '세션 정보를 불러오지 못했어요.'),
          data: (active) {
            if (active != null) {
              return Row(
                children: [
                  const Icon(Icons.sensors, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(child: Text('체크인됨 · 좌석 ${active.rigCode}')),
                  TextButton(onPressed: busy ? null : onCheckOut, child: const Text('체크아웃')),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('좌석 체크인', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: rigController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: '좌석 코드 (예: A-01)'),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: busy ? null : onCheckIn, child: const Text('체크인')),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(track.name),
        subtitle: Text(track.gameCode),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(
          '/rankings/${track.trackId}?trackName=${Uri.encodeComponent(track.name)}',
        ),
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
