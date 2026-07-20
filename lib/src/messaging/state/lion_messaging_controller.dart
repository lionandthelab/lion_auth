import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/lion_messaging_backend.dart';
import '../config/lion_messaging_config.dart';
import '../push/push_token_source.dart';

/// LionAuth 메시징 상태 컨트롤러 (ChangeNotifier).
///
/// 푸시 토큰 획득(push)과 저장/발송(backend)을 조합하고 busy/error/token 상태를
/// UI 에 노출한다. 로그인 컨트롤러([LionAuthController])와 **독립적**이며,
/// 호스트가 `onAuthenticated → onSignedIn(userId)` 로 단방향 연결한다.
///
/// Firebase 초기화(`Firebase.initializeApp`)는 호스트가 [initialize] 호출 전에
/// 수행한다(main_auth_lab.dart 가 `Supabase.initialize()` 를 부르는 것과 동일).
class LionMessagingController extends ChangeNotifier {
  LionMessagingController({
    required this.config,
    required this.backend,
    PushTokenSource? pushSource,
    this.onForegroundMessage,
  }) : pushSource = pushSource ?? createPushTokenSource();

  final LionMessagingConfig config;
  final LionMessagingBackend backend;
  final PushTokenSource pushSource;

  /// 포그라운드 수신 메시지 콜백(스낵바 표시 등).
  final void Function(PushMessage message)? onForegroundMessage;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _permissionGranted = false;
  bool get permissionGranted => _permissionGranted;

  String? _currentToken;
  String? get currentToken => _currentToken;

  PushMessage? _latestMessage;
  PushMessage? get latestMessage => _latestMessage;

  String? _userId;

  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<PushMessage>? _foregroundSub;

  bool get pushSupported => pushSource.isSupported;

  /// SDK 초기화 + 토큰 갱신/포그라운드 수신 구독. 앱 시작 후 1회 호출.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!config.enablePush) return;

    try {
      await pushSource.ensureInitialized();
    } catch (error) {
      debugPrint('[LionMessaging] push init failed: $error');
      return;
    }

    _tokenRefreshSub = pushSource.onTokenRefresh.listen(_onTokenRefreshed);
    _foregroundSub = pushSource.onForegroundMessage.listen((message) {
      _latestMessage = message;
      onForegroundMessage?.call(message);
      notifyListeners();
    });
  }

  /// 로그인 완료 시 호출. 자동 등록이 켜져 있으면 권한 요청 + 토큰 등록.
  Future<void> onSignedIn(String userId) async {
    _userId = userId;
    final fcm = config.fcm;
    if (!config.enablePush || fcm == null || !fcm.autoRegisterOnSignIn) return;
    await registerPush();
  }

  /// 로그아웃 시 호출. 서버 토큰 폐기 + 로컬 토큰 삭제.
  Future<void> onSignedOut() async {
    final token = _currentToken;
    await _guard(() async {
      if (token != null && token.isNotEmpty) {
        await backend.unregisterPushToken(token);
      }
      await pushSource.deleteToken();
      _currentToken = null;
      _userId = null;
    });
  }

  /// 알림 권한을 요청하고 결과를 상태에 반영.
  Future<bool> ensurePermission() async {
    final granted = await _guard(() => pushSource.requestPermission());
    _permissionGranted = granted ?? false;
    notifyListeners();
    return _permissionGranted;
  }

  /// 권한 요청(옵션) → 토큰 획득 → 서버 등록. 미지원 플랫폼은 조용히 건너뛴다.
  Future<void> registerPush() async {
    if (!pushSource.isSupported) return;
    final fcm = config.fcm;
    await _guard(() async {
      if (fcm?.requestPermissionOnRegister ?? true) {
        _permissionGranted = await pushSource.requestPermission();
        if (!_permissionGranted) {
          throw const LionMessagingException('알림 권한이 거부되어 등록하지 못했습니다.');
        }
      }
      final token = await pushSource.getToken(vapidKey: fcm?.vapidKey);
      if (token == null || token.isEmpty) {
        throw const LionMessagingException(
          '푸시 토큰을 발급받지 못했습니다. (웹은 VAPID 키/서비스워커 설정을 확인해 주세요)',
        );
      }
      await backend.registerPushToken(
        PushTokenRegistration(token: token, platform: pushSource.platform.wireName),
      );
      _currentToken = token;
    });
  }

  /// 알림톡/SMS/푸시 발송을 요청한다.
  Future<NotificationResult?> send(NotificationRequest request) {
    return _guard(() => backend.requestSend(request));
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _onTokenRefreshed(String token) async {
    _currentToken = token;
    if (_userId == null) return; // 로그인 상태에서만 재등록.
    await _guard(() async {
      await backend.registerPushToken(
        PushTokenRegistration(token: token, platform: pushSource.platform.wireName),
      );
    });
  }

  /// busy/error 를 관리하며 액션을 실행하고 결과를 반환(실패 시 null).
  Future<T?> _guard<T>(Future<T> Function() action) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await action();
    } on LionMessagingException catch (e) {
      _errorMessage = e.message;
      return null;
    } catch (error) {
      debugPrint('[LionMessaging] unexpected error: $error');
      _errorMessage = '알 수 없는 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    super.dispose();
  }
}
