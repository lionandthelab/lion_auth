// 설정 실수가 사용자 화면에 영어로 새지 않는가.
//
// `_koreanAuthMessage` 의 마지막 줄은 `'로그인에 실패했습니다. ($message)'` 다.
// GoTrue 가 id_token 의 `aud` 를 거절하면 그 영어 원문이 그대로 붙어 나간다 —
// 사용자는 "unable to ..." 를 보고, 개발자는 그게 **설정 불일치**라는 걸
// 메시지만으로는 알 수 없다.
//
// 이 실패는 운영자가 고쳐야 하는 종류다. 무엇을 봐야 하는지 말해 준다.

import 'package:flutter_test/flutter_test.dart';
import 'package:lion_auth/lion_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  String messageFor(AuthException e) =>
      SupabaseLionAuthBackend.describeAuthError(e);

  test('audience 불일치는 설정 문제로 안내한다', () {
    final message = messageFor(
      const AuthException('Unable to validate token: audience mismatch'),
    );
    expect(message, contains('Client ID'),
        reason: '어디를 고쳐야 하는지가 메시지에 없으면 영어 원문과 다를 바 없다');
    expect(message, isNot(startsWith('로그인에 실패했습니다. (Unable')));
  });

  test('프로바이더 비활성화는 기존대로 안내한다', () {
    final message =
        messageFor(const AuthException('Unsupported provider: provider is not enabled'));
    expect(message, contains('활성화'));
  });

  test('아는 실패는 원문을 노출하지 않는다', () {
    final message = messageFor(const AuthException('Invalid login credentials'));
    expect(message, '이메일 또는 비밀번호가 올바르지 않습니다.');
  });

  test('모르는 실패에도 원문은 남긴다', () {
    // 진단 단서를 통째로 지우면 운영이 눈을 잃는다. 다만 한국어 앞머리를 준다.
    final message = messageFor(const AuthException('some novel failure'));
    expect(message, contains('some novel failure'));
    expect(message, startsWith('로그인에 실패했습니다.'));
  });
}
