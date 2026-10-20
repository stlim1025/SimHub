import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/web_dialog.dart';
import '../../auth/domain/user_input_rules.dart';

/// 닉네임 변경 대화상자. 확인하면 다듬은 새 이름을 돌려준다 — 저장은 "변경 사항 저장"이 한다(docs/14 §8).
Future<String?> showChangeDisplayNameDialog(BuildContext context, {required String current}) =>
    showDialog<String>(context: context, builder: (_) => _ChangeDisplayNameDialog(current: current));

/// 이메일 변경 대화상자. [onSubmit]이 바로 서버에 저장한다. 성공하면 true.
/// [onSubmit]이 던진 [ApiException]은 필드별(새 이메일·현재 비밀번호) 또는 대화상자 아래에 보인다.
Future<bool?> showChangeEmailDialog(
  BuildContext context, {
  required Future<void> Function(String newEmail, String currentPassword) onSubmit,
}) =>
    showDialog<bool>(context: context, builder: (_) => _ChangeEmailDialog(onSubmit: onSubmit));

class _ChangeDisplayNameDialog extends StatefulWidget {
  const _ChangeDisplayNameDialog({required this.current});

  final String current;

  @override
  State<_ChangeDisplayNameDialog> createState() => _ChangeDisplayNameDialogState();
}

class _ChangeDisplayNameDialogState extends State<_ChangeDisplayNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_name.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebDialog(
      title: '닉네임 변경',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              key: const ValueKey('display-name-field'),
              controller: _name,
              autofocus: true,
              maxLength: kMaxDisplayNameLength,
              decoration: const InputDecoration(labelText: '새 닉네임'),
              validator: validateDisplayNameInput,
              onFieldSubmitted: (_) => _confirm(),
            ),
            Text(
              '"변경 사항 저장"을 눌러야 저장돼요.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        const WebDialogCancelButton(),
        WebDialogPrimaryButton(key: const ValueKey('display-name-confirm'), label: '확인', onPressed: _confirm),
      ],
    );
  }
}

class _ChangeEmailDialog extends StatefulWidget {
  const _ChangeEmailDialog({required this.onSubmit});

  final Future<void> Function(String newEmail, String currentPassword) onSubmit;

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  static const _newEmailField = 'newEmail';
  static const _currentPasswordField = 'currentPassword';
  static const _knownFields = [_newEmailField, _currentPasswordField];

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _submitting = false;
  Map<String, String> _fieldErrors = const {};
  String? _generalError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _fieldErrors = const {};
      _generalError = null;
    });
    try {
      await widget.onSubmit(_email.text.trim(), _password.text);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      // 이 대화상자의 칸(새 이메일·현재 비밀번호)에 해당하는 오류만 칸 아래에 보이고, 아니면 일반 메시지를 아래에 보인다.
      final known = {
        for (final field in _knownFields)
          field: ?e.fieldErrors[field],
      };
      _showError(fieldErrors: known, general: known.isEmpty ? e.message : null);
    } catch (e) {
      debugPrint('이메일 변경 실패: $e');
      _showError(general: _unexpectedError);
    }
  }

  static const _unexpectedError = '이메일을 바꾸지 못했어요. 잠시 후 다시 시도해 주세요.';

  void _showError({Map<String, String> fieldErrors = const {}, String? general}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _fieldErrors = fieldErrors;
      _generalError = general;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WebDialog(
      title: '이메일 변경',
      closeEnabled: !_submitting,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const ValueKey('email-new'),
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: '새 이메일', errorText: _fieldErrors[_newEmailField]),
              validator: validateEmailInput,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('email-password'),
              controller: _password,
              obscureText: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: '현재 비밀번호', errorText: _fieldErrors[_currentPasswordField]),
              validator: (v) => (v ?? '').isEmpty ? '현재 비밀번호를 입력해 주세요.' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_generalError != null) ...[
              const SizedBox(height: 12),
              Text(_generalError!, style: TextStyle(color: context.palette.danger)),
            ],
          ],
        ),
      ),
      actions: [
        WebDialogCancelButton(enabled: !_submitting),
        WebDialogPrimaryButton(
          key: const ValueKey('email-submit'),
          label: '변경',
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
