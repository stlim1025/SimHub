import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_notice.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/time/clock_provider.dart';
import '../../../core/util/relative_time.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/section_card.dart';
import '../application/devices_providers.dart';
import '../data/devices_repository.dart';
import '../domain/device_models.dart';

const String _revokeLabel = '연결 해제';
const String _revokeFailedText = '연결을 해제하지 못했어요. 잠시 후 다시 시도해 주세요.';
const String _emptyGuide = '위에서 발급한 연결 코드를 Agent에 입력하면 이 목록에 나타나요.';

/// 연결된 PC 목록과 [연결 해제](docs/11 §7.3 ④).
class ConnectedDevicesCard extends ConsumerStatefulWidget {
  const ConnectedDevicesCard({super.key});

  @override
  ConsumerState<ConnectedDevicesCard> createState() => _ConnectedDevicesCardState();
}

class _ConnectedDevicesCardState extends ConsumerState<ConnectedDevicesCard> {
  /// 확인 대화상자 후 해제하고 목록을 다시 불러온다. 실패하면 사유를 스낵바로 알린다.
  Future<void> _confirmAndRevoke(AgentDevice device) async {
    final messenger = AppToaster.of(context);
    final repo = ref.read(devicesRepositoryProvider);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _RevokeDialog(deviceName: device.name),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await repo.revoke(device.deviceId);
    } on ApiException catch (e) {
      messenger.show(e.message, tone: NoticeTone.error);
    } catch (e) {
      debugPrint('장치 연결 해제 실패: $e');
      messenger.show(_revokeFailedText, tone: NoticeTone.error);
    }
    if (mounted) {
      ref.invalidate(agentDevicesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(agentDevicesProvider);
    final now = ref.watch(clockProvider)();

    return SectionCard(
      title: '연결된 PC',
      trailing: IconButton(
        tooltip: '새로고침',
        icon: Icon(Icons.refresh, color: context.palette.textMuted),
        onPressed: () => ref.invalidate(agentDevicesProvider),
      ),
      child: devices.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => ErrorRetry(
          error: e,
          fallbackMessage: '연결된 PC를 불러오지 못했어요.',
          onRetry: () => ref.invalidate(agentDevicesProvider),
        ),
        data: (items) => items.isEmpty
            ? Text(_emptyGuide, style: TextStyle(color: context.palette.textMuted))
            : Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(),
                    _DeviceRow(
                      key: ValueKey('device-${items[i].deviceId}'),
                      device: items[i],
                      now: now,
                      onRevoke: () => _confirmAndRevoke(items[i]),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({super.key, required this.device, required this.now, required this.onRevoke});

  static final _dateFormat = DateFormat('yyyy-MM-dd');

  final AgentDevice device;
  final DateTime now;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final mutedSmall = Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted);
    final lastSeen = device.lastSeenAt;
    final lastSeenText = lastSeen == null ? '마지막 수신 없음' : '마지막 수신 ${describeAgo(now.difference(lastSeen))}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(Icons.desktop_windows_outlined, color: context.palette.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(lastSeenText, style: mutedSmall),
                Text('연결일 ${_dateFormat.format(device.createdAt.toLocal())}', style: mutedSmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onRevoke,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.palette.danger,
              minimumSize: const Size(96, 40),
            ),
            child: const Text(_revokeLabel),
          ),
        ],
      ),
    );
  }
}

class _RevokeDialog extends StatelessWidget {
  const _RevokeDialog({required this.deviceName});

  final String deviceName;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('이 PC의 연결을 해제할까요?'),
      content: Text(
        '"$deviceName"의 Agent는 더 이상 기록을 보낼 수 없어요. 다시 연결하려면 새 연결 코드가 필요해요.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          child: const Text(_revokeLabel),
        ),
      ],
    );
  }
}
