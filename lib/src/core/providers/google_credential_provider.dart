import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../config/lion_auth_config.dart';
import '../social_credential.dart';
import '../social_credential_provider.dart';

/// Google 자격 획득.
///
/// - Android/iOS: `GoogleSignIn.instance.authenticate()` 네이티브 시트.
/// - 웹: GIS 정책상 프로그래매틱 호출이 불가하므로 공식 렌더 버튼
///   (`renderGoogleWebButton()`)을 노출하고, 결과는 [credentialStream]으로 받는다.
class GoogleCredentialProvider extends SocialCredentialProvider {
  GoogleCredentialProvider(this.options);

  final GoogleAuthOptions options;

  final _credentialController = StreamController<SocialCredential>.broadcast();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _eventSubscription;
  bool _initialized = false;

  /// 웹 GIS 버튼 로그인 결과가 흘러오는 스트림.
  Stream<SocialCredential> get credentialStream => _credentialController.stream;

  @override
  bool get canAcquireInteractively =>
      GoogleSignIn.instance.supportsAuthenticate();

  @override
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    final signIn = GoogleSignIn.instance;
    if (kIsWeb) {
      // 웹에서는 serverClientId를 지원하지 않는다. clientId = 웹 클라이언트 ID.
      await signIn.initialize(clientId: options.webClientId);
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await signIn.initialize(
        clientId: options.iosClientId,
        serverClientId: options.webClientId,
      );
    } else {
      // Android: id_token audience를 웹 클라이언트 ID로 고정.
      await signIn.initialize(serverClientId: options.webClientId);
    }

    // 웹 GIS 버튼 경유 로그인은 이벤트 스트림으로만 도착한다.
    // 모바일은 authenticate() 반환값을 쓰므로 중복 방지를 위해 웹에서만 구독.
    if (kIsWeb) {
      _eventSubscription = signIn.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          final credential = _toCredential(event.user);
          if (credential != null) {
            _credentialController.add(credential);
          }
        }
      });
    }
  }

  @override
  Future<SocialCredential> acquire() async {
    await ensureInitialized();
    final signIn = GoogleSignIn.instance;
    if (!signIn.supportsAuthenticate()) {
      throw const SocialSignInException(
        '이 플랫폼에서는 Google 공식 버튼으로만 로그인할 수 있습니다.',
      );
    }

    try {
      final account = await signIn.authenticate();
      final credential = _toCredential(account);
      if (credential == null) {
        throw const SocialSignInException(
          'Google에서 ID 토큰을 받지 못했습니다. 클라이언트 ID 설정을 확인해 주세요.',
        );
      }
      return credential;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const SocialSignInCancelled();
      }
      throw SocialSignInException('Google 로그인에 실패했습니다. (${e.code.name})', e);
    }
  }

  SocialCredential? _toCredential(GoogleSignInAccount account) {
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) return null;
    return SocialCredential(
      provider: LionAuthProviderId.google,
      idToken: idToken,
      email: account.email,
      displayName: account.displayName,
    );
  }

  void dispose() {
    _eventSubscription?.cancel();
    _credentialController.close();
  }
}
