import 'package:flutter/material.dart';

import '../config/lion_auth_config.dart';
import '../config/lion_auth_theme.dart';
import '../state/lion_auth_controller.dart';
import 'social_login_buttons.dart';

/// 완성형 로그인/회원가입 화면.
///
/// 서비스는 [LionAuthController]와 [LionAuthTheme]만 주입하면 되고,
/// 로그인 성공 후 이동은 컨트롤러의 onAuthenticated 콜백에서 처리한다.
class LionAuthScreen extends StatefulWidget {
  const LionAuthScreen({
    super.key,
    required this.controller,
    this.theme = const LionAuthTheme(),
  });

  final LionAuthController controller;
  final LionAuthTheme theme;

  @override
  State<LionAuthScreen> createState() => _LionAuthScreenState();
}

class _LionAuthScreenState extends State<LionAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final Map<String, TextEditingController> _extraControllers = {};

  bool _isSignUpMode = false;
  bool _obscurePassword = true;

  LionAuthConfig get _config => widget.controller.config;
  LionAuthTheme get _theme => widget.theme;

  @override
  void initState() {
    super.initState();
    for (final field in _config.extraSignUpFields) {
      _extraControllers[field.key] = TextEditingController();
    }
    widget.controller.initialize();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    for (final controller in _extraControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_isSignUpMode) {
      final metadata = <String, dynamic>{};
      for (final field in _config.extraSignUpFields) {
        final value = _extraControllers[field.key]!.text.trim();
        if (value.isNotEmpty) metadata[field.key] = value;
      }
      await widget.controller.signUpWithPassword(
        email: _emailController.text,
        password: _passwordController.text,
        metadata: metadata,
      );
    } else {
      await widget.controller.signInWithPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
    }
  }

  Future<void> _onForgotPassword() async {
    final emailController = TextEditingController(text: _emailController.text);
    final requestedEmail = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('비밀번호 재설정'),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '가입한 이메일',
            hintText: 'you@example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(emailController.text.trim()),
            child: const Text('메일 보내기'),
          ),
        ],
      ),
    );
    if (requestedEmail == null || requestedEmail.isEmpty || !mounted) return;

    await widget.controller.sendPasswordReset(requestedEmail);
    if (!mounted) return;
    if (widget.controller.errorMessage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호 재설정 메일을 보냈습니다. 받은편지함을 확인해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final baseTheme = Theme.of(context);
    final localTheme = baseTheme.copyWith(
      scaffoldBackgroundColor: theme.background,
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: theme.primary,
        surface: theme.surface,
        error: theme.error,
      ),
      textTheme: theme.fontFamily == null
          ? baseTheme.textTheme
          : baseTheme.textTheme.apply(fontFamily: theme.fontFamily),
    );

    return Theme(
      data: localTheme,
      child: Scaffold(
        backgroundColor: theme.background,
        body: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            return Stack(
              children: [
                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 32,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _buildBody(theme),
                      ),
                    ),
                  ),
                ),
                if (widget.controller.isBusy)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.15),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(LionAuthTheme theme) {
    final errorMessage = widget.controller.errorMessage;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (theme.logo != null) ...[
          Center(child: theme.logo!),
          const SizedBox(height: 20),
        ],
        Text(
          _config.appName,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: theme.onBackground,
          ),
        ),
        if (_config.brandLine.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _config.brandLine,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: theme.mutedText),
          ),
        ],
        const SizedBox(height: 28),
        if (errorMessage != null) ...[
          Container(
            key: const ValueKey('lion_auth_error'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(theme.borderRadius),
              border: Border.all(color: theme.error.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: theme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorMessage,
                    style: TextStyle(fontSize: 13, color: theme.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_config.enableEmailPassword) ...[
          _buildEmailPasswordForm(theme),
          const SizedBox(height: 24),
          if (widget.controller.config.enabledProviders.isNotEmpty) ...[
            Row(
              children: [
                Expanded(child: Divider(color: theme.mutedText.withValues(alpha: 0.4))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '또는 간편 로그인',
                    style: TextStyle(fontSize: 12, color: theme.mutedText),
                  ),
                ),
                Expanded(child: Divider(color: theme.mutedText.withValues(alpha: 0.4))),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ],
        SocialLoginButtons(controller: widget.controller, theme: theme),
      ],
    );
  }

  Widget _buildEmailPasswordForm(LionAuthTheme theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('lion_auth_email'),
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: '이메일',
              prefixIcon: Icon(Icons.email_outlined, size: 20),
            ),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return '이메일을 입력해 주세요.';
              if (!email.contains('@') || !email.contains('.')) {
                return '올바른 이메일 형식이 아닙니다.';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const ValueKey('lion_auth_password'),
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: '비밀번호',
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (value) {
              if ((value ?? '').isEmpty) return '비밀번호를 입력해 주세요.';
              if (_isSignUpMode && (value ?? '').length < 6) {
                return '비밀번호는 6자 이상이어야 합니다.';
              }
              return null;
            },
          ),
          if (_isSignUpMode) ...[
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('lion_auth_confirm'),
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '비밀번호 확인',
                prefixIcon: Icon(Icons.lock_outline, size: 20),
              ),
              validator: (value) =>
                  value == _passwordController.text ? null : '비밀번호가 일치하지 않습니다.',
            ),
            for (final field in _config.extraSignUpFields) ...[
              const SizedBox(height: 14),
              TextFormField(
                key: ValueKey('lion_auth_extra_${field.key}'),
                controller: _extraControllers[field.key],
                decoration: InputDecoration(
                  labelText: field.label,
                  hintText: field.hint,
                  helperText: field.helper,
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                ),
                validator: (value) {
                  if (field.required && (value?.trim() ?? '').isEmpty) {
                    return '${field.label}을(를) 입력해 주세요.';
                  }
                  return null;
                },
              ),
            ],
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('lion_auth_submit'),
            onPressed: widget.controller.isBusy ? null : _onSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: _theme.primary,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_theme.borderRadius),
              ),
            ),
            child: Text(
              _isSignUpMode ? '회원가입' : '로그인',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                key: const ValueKey('lion_auth_toggle_mode'),
                onPressed: widget.controller.isBusy
                    ? null
                    : () {
                        setState(() => _isSignUpMode = !_isSignUpMode);
                        widget.controller.clearError();
                      },
                child: Text(
                  _isSignUpMode ? '이미 계정이 있어요' : '처음이에요, 가입할게요',
                  style: TextStyle(fontSize: 13, color: _theme.primary),
                ),
              ),
              if (!_isSignUpMode)
                TextButton(
                  onPressed:
                      widget.controller.isBusy ? null : _onForgotPassword,
                  child: Text(
                    '비밀번호를 잊었어요',
                    style: TextStyle(fontSize: 13, color: _theme.mutedText),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
