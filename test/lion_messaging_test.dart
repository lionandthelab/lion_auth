import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lion_auth/lion_auth.dart';

/// 백엔드 없이 컨트롤러 동작을 검증하기 위한 페이크.
class _FakeMessagingBackend implements LionMessagingBackend {
  final List<String> calls = [];
  NotificationResult sendResult =
      const NotificationResult(accepted: true, messageId: 'g1');
  bool failSend = false;

  @override
  Future<void> registerPushToken(PushTokenRegistration r) async {
    calls.add('register:${r.token}:${r.platform}');
  }

  @override
  Future<void> unregisterPushToken(String token) async {
    calls.add('unregister:$token');
  }

  @override
  Future<NotificationResult> requestSend(NotificationRequest req) async {
    calls.add('send:${req.channel.wireName}:${req.toUserIds.join(",")}');
    if (failSend) throw const LionMessagingException('발송에 실패했습니다.');
    return sendResult;
  }
}

/// firebase_messaging 없이 토큰 소스를 대체하는 페이크.
class _FakePushSource implements PushTokenSource {
  _FakePushSource({
    this.supported = true,
    this.permission = true,
  });

  final bool supported;
  final String? token = 'tok-1';
  final bool permission;
  final List<String> calls = [];
  final _refresh = StreamController<String>.broadcast();
  final _foreground = StreamController<PushMessage>.broadcast();

  @override
  PushPlatform get platform =>
      supported ? PushPlatform.android : PushPlatform.unsupported;

  @override
  bool get isSupported => supported;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<String?> getToken({String? vapidKey}) async => token;

  @override
  Stream<String> get onTokenRefresh => _refresh.stream;

  @override
  Future<void> deleteToken() async {
    calls.add('delete');
  }

  @override
  Stream<PushMessage> get onForegroundMessage => _foreground.stream;
}

LionMessagingController _controller(
  _FakeMessagingBackend backend,
  _FakePushSource push, {
  LionMessagingConfig? config,
}) {
  return LionMessagingController(
    config: config ?? const LionMessagingConfig(fcm: FcmOptions()),
    backend: backend,
    pushSource: push,
  );
}

void main() {
  group('직렬화', () {
    test('NotificationRequest.toMap 은 설정된 필드만 포함', () {
      const req = NotificationRequest(
        channel: NotificationChannel.auto,
        toUserIds: ['u1', 'u2'],
        templateId: 'KA01',
        variables: {'#{이름}': '홍길동'},
        body: '본문',
      );
      final map = req.toMap();
      expect(map['channel'], 'auto');
      expect(map['to_user_ids'], ['u1', 'u2']);
      expect(map['template_id'], 'KA01');
      expect(map['variables'], {'#{이름}': '홍길동'});
      expect(map['body'], '본문');
      expect(map.containsKey('title'), isFalse); // null 은 생략
    });

    test('NotificationResult.fromMap 파싱', () {
      final result = NotificationResult.fromMap({
        'accepted': true,
        'message_id': 'g1',
        'fallback_used': 'sms',
      });
      expect(result.accepted, isTrue);
      expect(result.messageId, 'g1');
      expect(result.fallbackUsed, 'sms');
    });

    test('PushTokenRegistration.toMap', () {
      const reg = PushTokenRegistration(
        token: 't1',
        platform: 'web',
        deviceId: 'd1',
      );
      final map = reg.toMap();
      expect(map['token'], 't1');
      expect(map['platform'], 'web');
      expect(map['device_id'], 'd1');
      expect(map.containsKey('app_version'), isFalse);
    });
  });

  group('LionMessagingController', () {
    test('registerPush 성공 → 백엔드 등록 + currentToken 설정', () async {
      final backend = _FakeMessagingBackend();
      final push = _FakePushSource();
      final controller = _controller(backend, push);
      addTearDown(controller.dispose);

      await controller.registerPush();

      expect(backend.calls, contains('register:tok-1:android'));
      expect(controller.currentToken, 'tok-1');
      expect(controller.errorMessage, isNull);
    });

    test('미지원 플랫폼 → 등록 건너뜀', () async {
      final backend = _FakeMessagingBackend();
      final push = _FakePushSource(supported: false);
      final controller = _controller(backend, push);
      addTearDown(controller.dispose);

      await controller.registerPush();

      expect(backend.calls, isEmpty);
      expect(controller.currentToken, isNull);
    });

    test('권한 거부 → 등록 실패 + 에러 메시지', () async {
      final backend = _FakeMessagingBackend();
      final push = _FakePushSource(permission: false);
      final controller = _controller(backend, push);
      addTearDown(controller.dispose);

      await controller.registerPush();

      expect(backend.calls, isEmpty);
      expect(controller.errorMessage, isNotNull);
    });

    test('send 성공 → NotificationResult 반환', () async {
      final backend = _FakeMessagingBackend();
      final controller = _controller(backend, _FakePushSource());
      addTearDown(controller.dispose);

      final result = await controller.send(const NotificationRequest(
        channel: NotificationChannel.push,
        toUserIds: ['u1'],
        title: '제목',
        body: '본문',
      ));

      expect(result?.accepted, isTrue);
      expect(result?.messageId, 'g1');
      expect(backend.calls, contains('send:push:u1'));
    });

    test('send 실패 → null + 한국어 에러', () async {
      final backend = _FakeMessagingBackend()..failSend = true;
      final controller = _controller(backend, _FakePushSource());
      addTearDown(controller.dispose);

      final result = await controller.send(const NotificationRequest(
        channel: NotificationChannel.sms,
        toUserIds: ['u1'],
        body: '본문',
      ));

      expect(result, isNull);
      expect(controller.errorMessage, '발송에 실패했습니다.');
    });

    test('onSignedIn(자동등록) → 등록, onSignedOut → 해제 + 토큰 삭제', () async {
      final backend = _FakeMessagingBackend();
      final push = _FakePushSource();
      final controller = _controller(
        backend,
        push,
        config: const LionMessagingConfig(
          fcm: FcmOptions(autoRegisterOnSignIn: true),
        ),
      );
      addTearDown(controller.dispose);

      await controller.onSignedIn('u1');
      expect(backend.calls, contains('register:tok-1:android'));

      await controller.onSignedOut();
      expect(backend.calls, contains('unregister:tok-1'));
      expect(push.calls, contains('delete'));
      expect(controller.currentToken, isNull);
    });
  });
}
