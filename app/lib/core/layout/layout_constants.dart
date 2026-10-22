import 'package:flutter/painting.dart';

/// 본문 최대 폭. 넓은 화면에서 줄이 지나치게 길어지는 것을 막는다.
const double kContentMaxWidth = 1100;

/// 그래프가 주인공인 화면(랩 상세 텔레메트리)의 본문 최대 폭. 큰 모니터에서 그래프 가로폭을 넓힌다.
const double kWideContentMaxWidth = 1680;

/// 셸 안 화면들의 공통 바깥 여백.
const EdgeInsets kPagePadding = EdgeInsets.all(20);
