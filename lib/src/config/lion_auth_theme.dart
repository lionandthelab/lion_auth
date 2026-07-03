import 'package:flutter/material.dart';

/// 서비스 브랜딩 주입용 테마.
///
/// 카카오(#FEE500)·네이버(#03C75A) 등 프로바이더 브랜드 색은 각사
/// 디자인 가이드라인상 고정이므로 여기서 바꾸지 않고 모듈 내부 상수로 둔다.
class LionAuthTheme {
  const LionAuthTheme({
    this.primary = const Color(0xFF5A4637),
    this.background = const Color(0xFFF9F7F2),
    this.surface = Colors.white,
    this.onBackground = const Color(0xFF3A3129),
    this.mutedText = const Color(0xFF8A8078),
    this.error = const Color(0xFFB3261E),
    this.borderRadius = 14,
    this.fontFamily,
    this.logo,
  });

  final Color primary;
  final Color background;
  final Color surface;
  final Color onBackground;
  final Color mutedText;
  final Color error;
  final double borderRadius;
  final String? fontFamily;

  /// 화면 상단에 표시할 로고 위젯 (선택).
  final Widget? logo;
}

/// 프로바이더 브랜드 고정 색상 (각사 가이드라인 준수 — 변경 금지).
abstract final class LionBrandColors {
  static const kakaoYellow = Color(0xFFFEE500);
  static const kakaoLabel = Color(0xD9000000); // 85% black
  static const naverGreen = Color(0xFF03C75A);
  static const googleBorder = Color(0xFF747775);
  static const appleBlack = Color(0xFF000000);
}
