import 'package:flutter/material.dart';
import '../state/lion_auth_controller.dart';
import '../config/lion_auth_theme.dart';

/// controller.isProcessing 동안 child 위에 로딩 오버레이를 덮는다.
/// 소셜 로그인(특히 리다이렉트 복귀) 처리 중 화면이 가만히 있어 혼동되는 것을 방지.
class LionAuthBusyOverlay extends StatelessWidget {
  const LionAuthBusyOverlay({
    super.key,
    required this.controller,
    required this.child,
    this.theme = const LionAuthTheme(),
    this.message = '로그인 처리 중...',
  });

  final LionAuthController controller;
  final Widget child;
  final LionAuthTheme theme;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Stack(
          children: [
            child,
            if (controller.isProcessing)
              Positioned.fill(
                child: AbsorbPointer(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
