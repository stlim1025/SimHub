import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/time/clock_provider.dart';
import '../../../core/widgets/error_retry.dart';
import '../application/devices_providers.dart';
import '../domain/connection_status.dart';
import '../domain/device_models.dart';

const double _dotSize = 12;
const double _dotGap = 12;
const String _title = 'Connection Status';
const String _telemetryAppPath = '/telemetry-app';

/// 연결 상태 카드(docs/11 §7.3). Dashboard와 Telemetry App에서 함께 쓴다.
/// [showSetupAction]이 true이고 연결된 PC가 없으면 Telemetry App으로 가는 버튼을 보여준다.
class ConnectionStatusCard extends ConsumerWidget {
  const ConnectionStatusCard({super.key, this.showSetupAction = true});

  final bool showSetupAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(agentDevicesProvider);
    final now = ref.watch(clockProvider)();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: devices.when(
          loading: () => const Center(
            child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorRetry(
            error: e,
            fallbackMessage: '연결 상태를 불러오지 못했어요.',
            onRetry: () => ref.invalidate(agentDevicesProvider),
          ),
          data: (items) => _StatusRow(
            devices: items,
            now: now,
            showSetupAction: showSetupAction,
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.devices, required this.now, required this.showSetupAction});

  final List<AgentDevice> devices;
  final DateTime now;
  final bool showSetupAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = connectionKindOf(devices, now);
    final dotColor = kind == ConnectionKind.receiving ? AppColors.success : context.palette.textMuted;

    return Row(
      children: [
        Container(
          width: _dotSize,
          height: _dotSize,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: _dotGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_title, style: theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted)),
              const SizedBox(height: 2),
              Text(
                connectionStatusText(devices, now),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (showSetupAction && kind == ConnectionKind.noDevices)
          FilledButton(
            onPressed: () => context.go(_telemetryAppPath),
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            child: const Text('연결하러 가기'),
          ),
      ],
    );
  }
}
