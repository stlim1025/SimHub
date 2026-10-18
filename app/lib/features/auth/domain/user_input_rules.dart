/// 가입·설정 화면이 함께 쓰는 입력 검증(서버 `UserInputRules`와 같은 규칙, docs/14 §5). 오류 메시지 또는 null.
library;

/// 닉네임(표시 이름) 최대 길이. 앞뒤 공백을 지운 뒤 센다.
const int kMaxDisplayNameLength = 50;

String? validateEmailInput(String? input) {
  final value = (input ?? '').trim();
  if (value.isEmpty) return '이메일을 입력해 주세요.';
  if (!value.contains('@') || !value.contains('.')) return '이메일 형식이 올바르지 않아요.';
  return null;
}

String? validateDisplayNameInput(String? input) {
  final value = (input ?? '').trim();
  if (value.isEmpty) return '닉네임을 입력해 주세요.';
  if (value.length > kMaxDisplayNameLength) return '닉네임은 $kMaxDisplayNameLength자 이하여야 해요.';
  return null;
}
