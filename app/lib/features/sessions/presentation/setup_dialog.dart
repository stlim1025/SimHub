import 'package:flutter/material.dart';

import '../../lap_detail/presentation/detail_list.dart';
import '../domain/setup_display.dart';

const String _title = 'Setup';
const String _closeLabel = '닫기';
const String _emptyText = '표시할 셋업 값이 없어요.';
const double _maxWidth = 440;
const double _groupGap = 16;

/// View Setup 대화상자(docs/15 §11.3 Details · Setup): 묶음(Aerodynamics·Transmission·…) 제목 + 키-값 목록.
Future<void> showSetupDialog(BuildContext context, Map<String, Object?> setup) => showDialog<void>(
      context: context,
      builder: (_) => SetupDialog(setup: setup),
    );

class SetupDialog extends StatelessWidget {
  const SetupDialog({super.key, required this.setup});

  final Map<String, Object?> setup;

  @override
  Widget build(BuildContext context) {
    final groups = setupGroups(setup);
    final titleStyle = Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold);
    return AlertDialog(
      title: const Text(_title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (groups.isEmpty) const Text(_emptyText),
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(height: _groupGap),
                Text(groups[i].title, style: titleStyle),
                DetailList(items: [for (final item in groups[i].items) DetailItem(item.label, text: item.value)]),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(_closeLabel)),
      ],
    );
  }
}
