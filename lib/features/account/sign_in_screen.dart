import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _phoneController;
  late final TextEditingController _otpController;
  bool _phoneOtpSent = false;
  bool _submitting = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _phoneController = TextEditingController();
    _otpController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = keyboardInset > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Account access')),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(20, keyboardOpen ? 10 : 18, 20, 28),
            children: [
              _AuthIntro(
                title: 'Welcome back',
                body:
                    'Sign in to open your tickets, manage RSVPs, and pick up where you left off without searching for links again.',
                compact: keyboardOpen,
              ),
              SizedBox(height: keyboardOpen ? 14 : 22),
              Form(
                key: _formKey,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          scrollPadding: const EdgeInsets.only(bottom: 180),
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (value) {
                            final trimmed = value?.trim() ?? '';
                            if (trimmed.isEmpty ||
                                !RegExp(
                                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                ).hasMatch(trimmed)) {
                              return 'Enter the email linked to your Vennuzo account.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          scrollPadding: const EdgeInsets.only(bottom: 180),
                          onFieldSubmitted: (_) {
                            if (!session.isProcessing && !_submitting) {
                              _submit();
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Password',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').isEmpty) {
                              return 'Enter your password.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: session.isProcessing || _submitting
                                ? null
                                : _submit,
                            child: Text(
                              session.isProcessing
                                  ? 'Signing you in...'
                                  : 'Continue with email',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: session.isProcessing
                              ? null
                              : _openResetDialog,
                          child: const Text('Forgot password?'),
                        ),
                        const SizedBox(height: 10),
                        const _SocialDivider(),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: _phoneOtpSent
                              ? TextInputAction.next
                              : TextInputAction.done,
                          scrollPadding: const EdgeInsets.only(bottom: 180),
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            hintText: '024 000 0000',
                          ),
                          onFieldSubmitted: (_) {
                            if (!session.isProcessing &&
                                !_submitting &&
                                !_phoneOtpSent) {
                              _requestPhoneOtp();
                            }
                          },
                        ),
                        if (_phoneOtpSent) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            maxLength: 6,
                            scrollPadding: const EdgeInsets.only(bottom: 180),
                            decoration: const InputDecoration(
                              labelText: 'Vennuzo code',
                              counterText: '',
                            ),
                            onFieldSubmitted: (_) {
                              if (!session.isProcessing && !_submitting) {
                                _verifyPhoneOtp();
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: session.isProcessing || _submitting
                                ? null
                                : (_phoneOtpSent
                                      ? _verifyPhoneOtp
                                      : _requestPhoneOtp),
                            icon: Icon(
                              _phoneOtpSent
                                  ? Icons.verified_user_outlined
                                  : Icons.sms_outlined,
                            ),
                            label: Text(
                              _phoneOtpSent
                                  ? 'Verify phone code'
                                  : 'Continue with phone',
                            ),
                          ),
                        ),
                        if (_phoneOtpSent) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: session.isProcessing || _submitting
                                ? null
                                : _requestPhoneOtp,
                            child: const Text('Resend Vennuzo code'),
                          ),
                        ],
                        const SizedBox(height: 8),
                        const _SocialDivider(),
                        const SizedBox(height: 12),
                        _SocialAuthButton(
                          label: 'Continue with Google',
                          icon: const Text(
                            'G',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          onPressed: session.isProcessing || _submitting
                              ? null
                              : _signInWithGoogle,
                        ),
                        const SizedBox(height: 10),
                        _SocialAuthButton(
                          label: 'Continue with G+',
                          icon: const Text(
                            'G+',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          onPressed: session.isProcessing || _submitting
                              ? null
                              : _signInWithGPlus,
                        ),
                        if (_showAppleButton) ...[
                          const SizedBox(height: 10),
                          _SocialAuthButton(
                            label: 'Continue with Apple',
                            icon: const Icon(Icons.apple, size: 20),
                            onPressed: session.isProcessing || _submitting
                                ? null
                                : _signInWithApple,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);

    final session = context.read<VennuzoSessionController>();
    final navigator = Navigator.of(context);
    try {
      await session.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
      await session.waitForAuthenticatedSession();
      if (!mounted) {
        return;
      }
      navigator.pop(true);
    } on VennuzoAuthFailure catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _requestPhoneOtp() async {
    if (_submitting) {
      return;
    }
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showMessage('Enter your phone number.');
      return;
    }
    if (phone.replaceAll(RegExp(r'[^0-9]'), '').length < 9) {
      _showMessage('Enter a valid phone number.');
      return;
    }
    setState(() => _submitting = true);

    final session = context.read<VennuzoSessionController>();
    try {
      final normalizedPhone = await session.requestPhoneLoginOtp(phone);
      if (!mounted) {
        return;
      }
      setState(() {
        _phoneController.text = normalizedPhone;
        _otpController.clear();
        _phoneOtpSent = true;
      });
      _showMessage('Vennuzo sent a sign-in code.');
    } on VennuzoAuthFailure catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _verifyPhoneOtp() async {
    if (_submitting) {
      return;
    }
    final phone = _phoneController.text.trim();
    final code = _otpController.text.trim();
    if (phone.isEmpty || code.length < 6) {
      _showMessage('Enter the 6-digit Vennuzo code.');
      return;
    }
    setState(() => _submitting = true);

    final session = context.read<VennuzoSessionController>();
    final navigator = Navigator.of(context);
    try {
      await session.verifyPhoneLoginOtp(phone: phone, code: code);
      await session.waitForAuthenticatedSession();
      if (!mounted) {
        return;
      }
      navigator.pop(true);
    } on VennuzoAuthFailure catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  bool get _showAppleButton {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
  }

  Future<void> _signInWithGoogle() async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    final session = context.read<VennuzoSessionController>();
    final navigator = Navigator.of(context);
    try {
      await session.signInWithGoogle();
      await session.waitForAuthenticatedSession();
      if (!mounted) {
        return;
      }
      navigator.pop(true);
    } on VennuzoAuthFailure catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _signInWithGPlus() async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    final session = context.read<VennuzoSessionController>();
    final navigator = Navigator.of(context);
    try {
      await session.signInWithGPlus();
      await session.waitForAuthenticatedSession();
      if (!mounted) {
        return;
      }
      navigator.pop(true);
    } on VennuzoAuthFailure catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _signInWithApple() async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    final session = context.read<VennuzoSessionController>();
    final navigator = Navigator.of(context);
    try {
      await session.signInWithApple();
      await session.waitForAuthenticatedSession();
      if (!mounted) {
        return;
      }
      navigator.pop(true);
    } on VennuzoAuthFailure catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _openResetDialog() async {
    final controller = TextEditingController(
      text: _emailController.text.trim(),
    );
    final submitted = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset password'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Send reset email'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (!mounted || submitted == null || submitted.isEmpty) {
      return;
    }

    try {
      await context.read<VennuzoSessionController>().sendPasswordReset(
        submitted,
      );
      if (!mounted) {
        return;
      }
      _showMessage('Password reset email sent.');
    } on VennuzoAuthFailure catch (error) {
      _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AuthIntro extends StatelessWidget {
  const _AuthIntro({
    required this.title,
    required this.body,
    required this.compact,
  });

  final String title;
  final String body;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: EdgeInsets.all(compact ? 18 : 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            VennuzoTheme.surfaceElevated,
            palette.teal.withValues(alpha: 0.42),
            VennuzoTheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: VennuzoTheme.borderBright),
        boxShadow: VennuzoTheme.shadowElevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.text.headlineSmall?.copyWith(color: Colors.white),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: compact
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      body,
                      style: context.text.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SocialDivider extends StatelessWidget {
  const _SocialDivider();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        Expanded(child: Divider(color: palette.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: context.text.bodyMedium),
        ),
        Expanded(child: Divider(color: palette.border)),
      ],
    );
  }
}

class _SocialAuthButton extends StatelessWidget {
  const _SocialAuthButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        child: ExcludeSemantics(
          child: OutlinedButton.icon(
            onPressed: onPressed,
            icon: icon,
            label: Text(label),
          ),
        ),
      ),
    );
  }
}
