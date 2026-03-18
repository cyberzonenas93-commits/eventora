import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<EventoraSessionController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              _AuthIntro(
                title: 'Welcome back',
                body:
                    'Sign in to open your tickets, manage RSVPs, and pick up where you left off without searching for links again.',
              ),
              const SizedBox(height: 22),
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
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (value) {
                            final trimmed = value?.trim() ?? '';
                            if (trimmed.isEmpty || !trimmed.contains('@')) {
                              return 'Enter the email linked to your Eventora account.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
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
                            onPressed: session.isProcessing ? null : _submit,
                            child: Text(
                              session.isProcessing
                                  ? 'Signing you in...'
                                  : 'Sign in',
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
                          onPressed: session.isProcessing
                              ? null
                              : _signInWithGoogle,
                        ),
                        if (_showAppleButton) ...[
                          const SizedBox(height: 10),
                          _SocialAuthButton(
                            label: 'Continue with Apple',
                            icon: const Icon(Icons.apple, size: 20),
                            onPressed: session.isProcessing
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final session = context.read<EventoraSessionController>();
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
    } on EventoraAuthFailure catch (error) {
      _showMessage(error.message);
    }
  }

  bool get _showAppleButton {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
  }

  Future<void> _signInWithGoogle() async {
    final session = context.read<EventoraSessionController>();
    final navigator = Navigator.of(context);
    try {
      await session.signInWithGoogle();
      await session.waitForAuthenticatedSession();
      if (!mounted) {
        return;
      }
      navigator.pop(true);
    } on EventoraAuthFailure catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _signInWithApple() async {
    final session = context.read<EventoraSessionController>();
    final navigator = Navigator.of(context);
    try {
      await session.signInWithApple();
      await session.waitForAuthenticatedSession();
      if (!mounted) {
        return;
      }
      navigator.pop(true);
    } on EventoraAuthFailure catch (error) {
      _showMessage(error.message);
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
      await context.read<EventoraSessionController>().sendPasswordReset(
        submitted,
      );
      if (!mounted) {
        return;
      }
      _showMessage('Password reset email sent.');
    } on EventoraAuthFailure catch (error) {
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
  const _AuthIntro({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [palette.ink, palette.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.text.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
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
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(label),
      ),
    );
  }
}
