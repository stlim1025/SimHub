import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/time/clock_provider.dart';
import '../../../core/util/relative_time.dart';
import '../../../core/widgets/section_card.dart';
import '../application/devices_providers.dart';
import '../domain/device_models.dart';

/// 남은 시간을 갱신하는 주기.
const Duration _tick = Duration(seconds: 1);

const double _codeFontSize = 32;
const double _codeLetterSpacing = 4;
const double _buttonHeight = 44;
const double _spinnerSize = 24;

const String _issueLabel = '연결 코드 발급';
const String _reissueLabel = '다시 발급';
const String _issueFailedText = '연결 코드를 발급하지 못했어요. 잠시 후 다시 시도해 주세요.';
const String _copyFailedText = '복사하지 못했어요. 코드를 직접 선택해 복사해 주세요.';

/// 연결 코드 발급·남은 시간·복사(docs/11 §7.3 ②).
/// 코드는 민감 정보이므로 화면에만 보이고 로그에는 남기지 않는다.
class PairingCodeCard extends ConsumerWidget {
  const PairingCodeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pairingCodeControllerProvider);
    final controller = ref.read(pairingCodeControllerProvider.notifier);
    // 발급이 실패한 AsyncError는 직전 값(만료된 코드)을 그대로 들고 있다.
    // 오류가 있으면 그 코드를 다시 보여주지 않고 오류와 발급 버튼만 보인다.
    final code = state.hasError ? null : state.valueOrNull;

    return SectionCard(
      title: '연결 코드',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Agent에 코드를 입력하면 이 계정에 PC가 연결돼요. 코드는 10분 동안 한 번만 쓸 수 있고, '
            '새로 발급하면 이전 코드는 쓸 수 없어요.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
          ),
          const SizedBox(height: 16),
          if (state.isLoading)
            const SizedBox(
              height: _buttonHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: _spinnerSize,
                  height: _spinnerSize,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            )
          else if (code != null)
            _IssuedCode(key: ValueKey(code.code), code: code, onReissue: controller.issue)
          else ...[
            if (state.hasError) _IssueError(error: state.error!),
            _IssueButton(label: _issueLabel, onPressed: controller.issue),
          ],
        ],
      ),
    );
  }
}

class _IssueButton extends StatelessWidget {
  const _IssueButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size(140, _buttonHeight)),
      child: Text(label),
    );
  }
}

class _IssueError extends StatelessWidget {
  const _IssueError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = error is ApiException ? (error as ApiException).message : _issueFailedText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(message, style: const TextStyle(color: AppColors.danger)),
    );
  }
}

/// 발급된 코드와 1초마다 갱신되는 남은 시간. 만료되면 타이머를 멈추고 다시 발급을 권한다.
/// 코드마다 새 State가 생기도록 호출부에서 코드 값을 key로 준다.
class _IssuedCode extends ConsumerStatefulWidget {
  const _IssuedCode({super.key, required this.code, required this.onReissue});

  final PairingCode code;
  final VoidCallback onReissue;

  @override
  ConsumerState<_IssuedCode> createState() => _IssuedCodeState();
}

class _IssuedCodeState extends ConsumerState<_IssuedCode> {
  Timer? _timer;

  Duration _remaining() => widget.code.expiresAt.difference(ref.read(clockProvider)());

  @override
  void initState() {
    super.initState();
    if (_remaining() > Duration.zero) {
      _timer = Timer.periodic(_tick, (_) => _onTick());
    }
  }

  void _onTick() {
    if (_remaining() <= Duration.zero) {
      _timer?.cancel();
      _timer = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: widget.code.code));
      messenger.showSnackBar(const SnackBar(content: Text('복사했어요')));
    } on PlatformException {
      messenger.showSnackBar(const SnackBar(content: Text(_copyFailedText)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _remaining();
    final expired = remaining <= Duration.zero;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.code.code,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: _codeFontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: _codeLetterSpacing,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: expired ? context.palette.textMuted : context.palette.textPrimary,
            decoration: expired ? TextDecoration.lineThrough : null,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (!expired) ...[
              Text('남은 시간 ', style: theme.textTheme.bodyMedium?.copyWith(color: context.palette.textMuted)),
            ],
            Text(
              formatRemaining(remaining),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: expired ? AppColors.danger : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (expired)
          _IssueButton(label: _reissueLabel, onPressed: widget.onReissue)
        else
          OutlinedButton.icon(
            onPressed: _copy,
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('복사'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(120, _buttonHeight)),
          ),
      ],
    );
  }
}
