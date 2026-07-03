import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../config/lion_auth_config.dart';
import '../social_credential.dart';
import '../social_credential_provider.dart';

/// Apple 자격 획득 (iOS/macOS).
///
/// iOS에서 타사 소셜 로그인을 제공하면 App Store 심사 지침 4.8에 따라
/// Apple 로그인 제공이 사실상 필수다.
class AppleCredentialProvider extends SocialCredentialProvider {
  AppleCredentialProvider(this.options);

  final AppleAuthOptions options;

  @override
  Future<SocialCredential> acquire() async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const SocialSignInCancelled();
      }
      throw SocialSignInException('Apple 로그인에 실패했습니다. (${e.code.name})', e);
    }

    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw const SocialSignInException('Apple에서 ID 토큰을 받지 못했습니다.');
    }

    final fullName = [credential.givenName, credential.familyName]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join(' ');

    return SocialCredential(
      provider: LionAuthProviderId.apple,
      idToken: idToken,
      rawNonce: rawNonce,
      email: credential.email,
      displayName: fullName.isEmpty ? null : fullName,
    );
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }
}
