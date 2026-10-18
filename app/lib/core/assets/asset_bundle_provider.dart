import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 앱 자산 묶음. 기본은 [rootBundle], 테스트에서 가짜로 바꿔 끼운다(전역 정적 대신 주입).
final assetBundleProvider = Provider<AssetBundle>((ref) => rootBundle);
