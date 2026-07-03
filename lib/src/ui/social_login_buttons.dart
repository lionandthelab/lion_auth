import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/lion_auth_config.dart';
import '../config/lion_auth_theme.dart';
import '../state/lion_auth_controller.dart';
import 'google_web_button_stub.dart'
    if (dart.library.js_interop) 'google_web_button_web.dart';

/// 소셜 로그인 버튼 묶음.
///
/// - 원형 아이콘 버튼 행: Kakao / Naver / (모바일) Google / (iOS) Apple
/// - 웹 Google: GIS 정책상 공식 렌더 버튼을 별도 행으로 노출.
class SocialLoginButtons extends StatelessWidget {
  const SocialLoginButtons({
    super.key,
    required this.controller,
    this.theme = const LionAuthTheme(),
  });

  final LionAuthController controller;
  final LionAuthTheme theme;

  @override
  Widget build(BuildContext context) {
    final providers = controller.config.enabledProviders;
    if (providers.isEmpty) return const SizedBox.shrink();

    final googleUsesWebButton =
        kIsWeb && providers.contains(LionAuthProviderId.google);
    final iconProviders = providers
        .where((id) => !(kIsWeb && id == LionAuthProviderId.google))
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (iconProviders.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final id in iconProviders)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: _SocialIconButton(
                    provider: id,
                    onTap: controller.isBusy
                        ? null
                        : () => controller.signInWithSocial(id),
                  ),
                ),
            ],
          ),
        if (googleUsesWebButton) ...[
          if (iconProviders.isNotEmpty) const SizedBox(height: 16),
          // GIS 공식 버튼 — 스타일은 Google이 렌더링한다.
          Center(child: renderGoogleWebButton()),
        ],
      ],
    );
  }
}

class _SocialIconButton extends StatelessWidget {
  const _SocialIconButton({required this.provider, required this.onTap});

  final LionAuthProviderId provider;
  final VoidCallback? onTap;

  static const _labels = {
    LionAuthProviderId.google: 'Google로 로그인',
    LionAuthProviderId.kakao: '카카오로 로그인',
    LionAuthProviderId.naver: '네이버로 로그인',
    LionAuthProviderId.apple: 'Apple로 로그인',
  };

  @override
  Widget build(BuildContext context) {
    final (background, border, mark) = switch (provider) {
      LionAuthProviderId.google => (
          Colors.white,
          LionBrandColors.googleBorder,
          const CustomPaint(
            size: Size(24, 24),
            painter: _GoogleMarkPainter(),
          ) as Widget,
        ),
      LionAuthProviderId.kakao => (
          LionBrandColors.kakaoYellow,
          null,
          const CustomPaint(
            size: Size(24, 24),
            painter: _KakaoMarkPainter(),
          ) as Widget,
        ),
      LionAuthProviderId.naver => (
          LionBrandColors.naverGreen,
          null,
          const CustomPaint(
            size: Size(18, 18),
            painter: _NaverMarkPainter(),
          ) as Widget,
        ),
      LionAuthProviderId.apple => (
          LionBrandColors.appleBlack,
          null,
          const Icon(Icons.apple, color: Colors.white, size: 28) as Widget,
        ),
    };

    final label = _labels[provider]!;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: background,
          shape: CircleBorder(
            side: border == null
                ? BorderSide.none
                : BorderSide(color: border, width: 1),
          ),
          elevation: 1,
          child: InkWell(
            key: ValueKey('lion_auth_social_${provider.name}'),
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Center(child: mark),
            ),
          ),
        ),
      ),
    );
  }
}

/// Google 'G' 마크 (간략화 4색 아크 + 바).
class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.20;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    double rad(double deg) => deg * math.pi / 180;
    // 3시 방향이 0°, 시계 방향 진행.
    canvas.drawArc(rect, rad(0), rad(75), false, paint..color = _blue);
    canvas.drawArc(rect, rad(75), rad(75), false, paint..color = _green);
    canvas.drawArc(rect, rad(150), rad(75), false, paint..color = _yellow);
    canvas.drawArc(rect, rad(225), rad(90), false, paint..color = _red);

    // 오른쪽 가로 바.
    final barPaint = Paint()..color = _blue;
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.5,
        size.height * 0.5 - stroke / 2,
        size.width * 0.5,
        stroke,
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Kakao 말풍선 마크.
class _KakaoMarkPainter extends CustomPainter {
  const _KakaoMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = LionBrandColors.kakaoLabel;
    final w = size.width;
    final h = size.height;

    // 몸통: 넓은 타원형 말풍선.
    final bubble = Rect.fromLTWH(0, 0, w, h * 0.82);
    canvas.drawOval(bubble, paint);

    // 꼬리: 왼쪽 아래로 향하는 삼각형.
    final tail = Path()
      ..moveTo(w * 0.28, h * 0.68)
      ..lineTo(w * 0.20, h)
      ..lineTo(w * 0.50, h * 0.78)
      ..close();
    canvas.drawPath(tail, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Naver 'N' 마크.
class _NaverMarkPainter extends CustomPainter {
  const _NaverMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.36, 0)
      ..lineTo(w * 0.64, h * 0.52)
      ..lineTo(w * 0.64, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w * 0.64, h)
      ..lineTo(w * 0.36, h * 0.48)
      ..lineTo(w * 0.36, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
