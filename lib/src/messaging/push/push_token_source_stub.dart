import 'push_token_source.dart';

/// 미지원 플랫폼(예: Windows/Linux 데스크톱)용 스텁.
///
/// 모든 조작이 무해하게 no-op 이며, 토큰은 항상 null 이라 등록을 건너뛴다.
class StubPushTokenSource implements PushTokenSource {
  @override
  PushPlatform get platform => PushPlatform.unsupported;

  @override
  bool get isSupported => false;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> getToken({String? vapidKey}) async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Future<void> deleteToken() async {}

  @override
  Stream<PushMessage> get onForegroundMessage => const Stream.empty();
}

PushTokenSource makePushTokenSource() => StubPushTokenSource();
