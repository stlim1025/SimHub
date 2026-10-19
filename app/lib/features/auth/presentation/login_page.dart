import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_notice.dart';
import '../application/auth_controller.dart';
import '../domain/user_input_rules.dart';

// 웹 로그인 카드 치수(F1Laps 로그인·가입 화면 참고).
const double _cardMaxWidth = 512;
const double _cardRadius = 8;
const double _bodyPaddingX = 40;
const double _bodyPaddingTop = 40;
const double _bodyPaddingBottom = 32;
const double _footerPadding = 28;
const double _titleFontSize = 28;
const double _titleGap = 32;
const double _labelGap = 6;
const double _fieldGap = 20;
const double _submitGap = 28;
const double _submitHeight = 40;
const double _captionGap = 8;
const double _progressSize = 20;

/// 로그인/회원가입 화면. 클라이언트 입력 검증 후 서버에 위임(서버가 최종 권위).
/// 테두리 카드 안에 큰 제목 · 이름표 위 입력칸 · 꽉 찬 버튼, 구분선 아래에 모드 전환(F1Laps 배치).
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

  /// 폼 위 오류 배너 문구(웹 화면처럼 그 자리에서 알린다 — 아래에서 올라오는 알림은 쓰지 않는다). null = 없음.
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // 버튼은 진행 중 비활성이지만 키보드 엔터는 막히지 않으므로 여기서도 이중 제출을 막는다.
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final controller = ref.read(authControllerProvider.notifier);
      if (_registerMode) {
        await controller.register(_email.text.trim(), _password.text, _displayName.text.trim());
      } else {
        await controller.login(_email.text.trim(), _password.text);
      }
      // 성공 시 라우터 redirect가 Dashboard(/)로 이동시킨다.
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '로그인 중 문제가 발생했어요. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _toggleMode() => setState(() {
        _registerMode = !_registerMode;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _cardMaxWidth),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(_cardRadius),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(_bodyPaddingX, _bodyPaddingTop, _bodyPaddingX, _bodyPaddingBottom),
                      child: _buildForm(palette, textTheme),
                    ),
                    Divider(height: 1, color: palette.border),
                    Padding(
                      padding: const EdgeInsets.all(_footerPadding),
                      child: Column(
                        children: [
                          Text(_registerMode ? '이미 계정이 있나요?' : '처음이신가요?', style: const TextStyle(fontWeight: FontWeight.w500)),
                          const SizedBox(height: _captionGap),
                          FilledButton(
                            key: const ValueKey('login-toggle-mode'),
                            onPressed: _submitting ? null : _toggleMode,
                            style: FilledButton.styleFrom(
                              backgroundColor: palette.background,
                              foregroundColor: palette.textPrimary,
                            ),
                            child: Text(_registerMode ? '로그인하기' : '회원가입하기'),
                          ),
                        ],
                      ),
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

  Widget _buildForm(AppPalette palette, TextTheme textTheme) {
    InputDecoration field(String hint) => InputDecoration(hintText: hint, fillColor: palette.background);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _registerMode ? '${AppConfig.brandName} 회원가입' : '${AppConfig.brandName} 로그인',
            textAlign: TextAlign.center,
            style: textTheme.headlineMedium?.copyWith(fontSize: _titleFontSize, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: _titleGap),
          if (_error != null) ...[
            NoticeBanner(key: const ValueKey('login-error'), message: _error!, tone: NoticeTone.error),
            const SizedBox(height: _fieldGap),
          ],
          const _FieldLabel('이메일'),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: field('이메일'),
            validator: validateEmailInput,
          ),
          const SizedBox(height: _fieldGap),
          const _FieldLabel('비밀번호'),
          TextFormField(
            controller: _password,
            obscureText: true,
            // 로그인에서는 비밀번호가 마지막 입력이라 엔터가 제출, 가입에서는 닉네임으로 이동.
            textInputAction: _registerMode ? TextInputAction.next : TextInputAction.done,
            onFieldSubmitted: _registerMode ? null : (_) => _submit(),
            autofillHints: const [AutofillHints.password],
            decoration: field('비밀번호'),
            validator: (v) {
              if ((v ?? '').isEmpty) return '비밀번호를 입력해 주세요.';
              if (_registerMode && (v ?? '').length < 8) return '비밀번호는 8자 이상이어야 해요.';
              return null;
            },
          ),
          if (_registerMode) ...[
            const SizedBox(height: _fieldGap),
            const _FieldLabel('닉네임'),
            TextFormField(
              controller: _displayName,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: field('닉네임'),
              validator: validateDisplayNameInput,
            ),
          ],
          const SizedBox(height: _submitGap),
          SizedBox(
            height: _submitHeight,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox.square(dimension: _progressSize, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_registerMode ? '가입하기' : '로그인'),
            ),
          ),
          if (_registerMode) ...[
            const SizedBox(height: _captionGap),
            Text(
              '무료 계정이에요 — 결제 정보는 받지 않아요.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// 입력칸 위 굵은 이름표.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: _labelGap),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}
