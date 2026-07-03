import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/lion_auth_backend.dart';
import '../config/lion_auth_config.dart';
import '../core/providers/apple_credential_provider.dart';
import '../core/providers/google_credential_provider.dart';
import '../core/providers/kakao_credential_provider.dart';
import '../core/providers/naver_credential_provider.dart';
import '../core/social_credential.dart';
import '../core/social_credential_provider.dart';

/// LionAuth 상태 컨트롤러 (ChangeNotifier).
///
/// 자격 획득(core)과 세션 발급(backend)을 조합하고,
/// busy/error/session 상태를 UI에 노출한다.
class LionAuthController extends ChangeNotifier {
  LionAuthController({
    required this.config,
    required this.backend,
    this.onAuthenticated,
  }) {
    final google = config.google;
    if (google != null) {
      _providers[LionAuthProviderId.google] = GoogleCredentialProvider(google);
    }
    final kakao = config.kakao;
    if (kakao != null) {
      _providers[LionAuthProviderId.kakao] = KakaoCredentialProvider(kakao);
    }
    final naver = config.naver;
    if (naver != null) {
      _providers[LionAuthProviderId.naver] = NaverCredentialProvider(naver);
    }
    final apple = config.apple;
    if (apple != null) {
      _providers[LionAuthProviderId.apple] = AppleCredentialProvider(apple);
    }
  }

  final LionAuthConfig config;
  final LionAuthBackend backend;

  /// 세션 발급 성공 시 호출.
  final void Function(LionAuthSession session)? onAuthenticated;

  final Map<LionAuthProviderId, SocialCredentialProvider> _providers = {};
  StreamSubscription<SocialCredential>? _googleWebSubscription;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  LionAuthSession? _session;
  LionAuthSession? get session => _session;
  bool get isLoggedIn => _session != null;

  bool _initialized = false;

  SocialCredentialProvider? providerOf(LionAuthProviderId id) =>
      _providers[id];

  /// SDK 초기화 + 웹 리다이렉트 복귀 자격 회수. 앱 시작 후 1회 호출.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    for (final provider in _providers.values) {
      try {
        await provider.ensureInitialized();
      } catch (error) {
        debugPrint('[LionAuth] provider init failed: $error');
      }
    }

    // 웹 Google: GIS 렌더 버튼 로그인 결과는 스트림으로 도착한다.
    final google = _providers[LionAuthProviderId.google];
    if (google is GoogleCredentialProvider && kIsWeb) {
      _googleWebSubscription =
          google.credentialStream.listen(_signInWithAcquiredCredential);
    }

    // Naver 웹 리다이렉트 복귀 등, 시작 시점에 회수할 자격 처리.
    for (final provider in _providers.values) {
      try {
        final pending = await provider.resumePendingCredential();
        if (pending != null) {
          await _signInWithAcquiredCredential(pending);
          break;
        }
      } on SocialSignInException catch (e) {
        _errorMessage = e.message;
        notifyListeners();
      }
    }
  }

  /// 소셜 버튼 탭 진입점.
  Future<void> signInWithSocial(LionAuthProviderId id) async {
    final provider = _providers[id];
    if (provider == null) {
      _fail('${id.name} 로그인이 설정되지 않았습니다.');
      return;
    }

    await _run(() async {
      final SocialCredential credential;
      try {
        credential = await provider.acquire();
      } on SocialSignInCancelled {
        return; // 사용자가 취소 — 에러 아님.
      } on SocialSignInException catch (e) {
        _errorMessage = e.message;
        return;
      }
      await _completeSignIn(credential);
    });
  }

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) =>
      _run(() async {
        try {
          final session = await backend.signInWithPassword(
            email: email.trim(),
            password: password,
          );
          _succeed(session);
        } on LionAuthBackendException catch (e) {
          _errorMessage = e.message;
        }
      });

  Future<void> signUpWithPassword({
    required String email,
    required String password,
    Map<String, dynamic> metadata = const {},
  }) =>
      _run(() async {
        try {
          final session = await backend.signUpWithPassword(
            email: email.trim(),
            password: password,
            metadata: metadata,
          );
          _succeed(session);
        } on LionAuthBackendException catch (e) {
          _errorMessage = e.message;
        }
      });

  Future<void> sendPasswordReset(String email) => _run(() async {
        try {
          await backend.sendPasswordReset(email.trim());
        } on LionAuthBackendException catch (e) {
          _errorMessage = e.message;
        }
      });

  Future<void> signOut() => _run(() async {
        await backend.signOut();
        _session = null;
      });

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _signInWithAcquiredCredential(SocialCredential credential) =>
      _run(() => _completeSignIn(credential));

  Future<void> _completeSignIn(SocialCredential credential) async {
    try {
      final session = await backend.signInWithCredential(credential);
      _succeed(session);
    } on LionAuthBackendException catch (e) {
      _errorMessage = e.message;
    }
  }

  void _succeed(LionAuthSession session) {
    _session = session;
    _errorMessage = null;
    onAuthenticated?.call(session);
  }

  void _fail(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_isBusy) return;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      debugPrint('[LionAuth] unexpected error: $error');
      _errorMessage = '알 수 없는 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _googleWebSubscription?.cancel();
    final google = _providers[LionAuthProviderId.google];
    if (google is GoogleCredentialProvider) {
      google.dispose();
    }
    super.dispose();
  }
}
