import 'package:flutter/painting.dart';

/// 본문 최대 폭(B안 개편: 화면 전체를 쓴다). 이보다 넓은 초광폭 모니터에서만 가운데로 모은다.
const double kContentMaxWidth = 1920;

/// 그래프가 주인공인 화면(랩 상세·하이라이트)의 본문 최대 폭. 초광폭 모니터에서도 그래프 가로폭을 넓힌다.
const double kWideContentMaxWidth = 2400;

/// 글을 읽는 화면(설정·리더보드 TOP10 등)의 본문 폭. 전체 폭으로 늘리면 줄이 너무 길어진다.
const double kReadableContentMaxWidth = 1100;

/// 셸 안 화면들의 공통 바깥 여백.
const EdgeInsets kPagePadding = EdgeInsets.all(20);
