import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi_web;

/// 웹 전용: GIS(Google Identity Services) 공식 렌더 버튼.
///
/// GIS 정책상 웹에서는 프로그래매틱 로그인 호출이 불가하므로
/// 이 버튼을 통해서만 자격을 획득할 수 있다. 로그인 결과는
/// GoogleCredentialProvider.credentialStream으로 전달된다.
Widget renderGoogleWebButton() => gsi_web.renderButton();
