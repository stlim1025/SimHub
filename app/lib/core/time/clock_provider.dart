import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 현재 시각 공급원. 위젯·로직은 `DateTime.now()`를 직접 부르지 않고 이 provider로 시각을 얻는다
/// (헌장: 시간 추상화). 테스트에서는 고정·가변 시계로 override한다.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
