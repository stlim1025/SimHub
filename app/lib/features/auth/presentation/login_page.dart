import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../application/auth_controller.dart';

/// 로그인/회원가입 화면. 클라이언트 입력 검증 후 서버에 위임(서버가 최종 권위).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  bool _registerMode = false;
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final controller = ref.read(authControllerProvider.notifier);
      if (_registerMode) {
        await controller.register(_email.text.trim(), _password.text, _displayName.text.trim());
      } else {
        await controller.login(_email.text.trim(), _password.text);
      }
      // 성공 시 라우터 redirect가 /home으로 이동시킨다.
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인 중 문제가 발생했어요. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('SimCenter',
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_registerMode ? '회원가입' : '로그인', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: '이메일'),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return '이메일을 입력해 주세요.';
                        if (!value.contains('@') || !value.contains('.')) return '이메일 형식이 올바르지 않아요.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: '비밀번호'),
                      validator: (v) {
                        if ((v ?? '').isEmpty) return '비밀번호를 입력해 주세요.';
                        if (_registerMode && (v ?? '').length < 8) return '비밀번호는 8자 이상이어야 해요.';
                        return null;
                      },
                    ),
                    if (_registerMode) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _displayName,
                        decoration: const InputDecoration(labelText: '닉네임'),
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return '닉네임을 입력해 주세요.';
                          if (value.length > 50) return '닉네임은 50자 이하여야 해요.';
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_registerMode ? '가입하고 시작하기' : '로그인'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _registerMode = !_registerMode),
                      child: Text(_registerMode ? '이미 계정이 있어요 · 로그인' : '처음이신가요? · 회원가입'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
