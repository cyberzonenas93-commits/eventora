import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import 'legal_links.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _dobController;
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmPasswordController;
  DateTime? _selectedDateOfBirth;
  final _imagePicker = ImagePicker();
  XFile? _selectedProfileImage;
  Uint8List? _selectedProfileImageBytes;
  bool _submitted = false;
  late final TapGestureRecognizer _termsTapRecognizer;
  late final TapGestureRecognizer _privacyTapRecognizer;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _dobController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _termsTapRecognizer = TapGestureRecognizer()
      ..onTap = () => _openLegalUrl(
        VennuzoLegalLinks.termsOfService,
        'Could not open the Terms of Service.',
      );
    _privacyTapRecognizer = TapGestureRecognizer()
      ..onTap = () => _openLegalUrl(
        VennuzoLegalLinks.privacyPolicy,
        'Could not open the Privacy Policy.',
      );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _termsTapRecognizer.dispose();
    _privacyTapRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            _AuthIntro(
              title: 'Create your Vennuzo account',
              body:
                  'Save tickets, RSVP faster, and keep your plans in one place. Add your date of birth now, and include a contact number if you want hosts to have it.',
            ),
            const SizedBox(height: 22),
            Form(
              key: _formKey,
              autovalidateMode: _submitted
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _ProfileImagePicker(
                        imageBytes: _selectedProfileImageBytes,
                        onPick: _pickProfileImage,
                        onRemove: _selectedProfileImageBytes == null
                            ? null
                            : _removeProfileImage,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                        ),
                        onChanged: (_) => _validateAfterSubmit(),
                        validator: (value) {
                          if ((value ?? '').trim().length < 2) {
                            return 'Add the name you want people to see.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                        onChanged: (_) => _validateAfterSubmit(),
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty || !trimmed.contains('@')) {
                            return 'Enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Contact number (optional)',
                        ),
                      ),
                      const SizedBox(height: 14),
                      Semantics(
                        button: true,
                        label: 'Date of birth',
                        value: _dobController.text.isEmpty
                            ? 'Not selected'
                            : _dobController.text,
                        hint: 'Opens date picker',
                        onTap: _pickDateOfBirth,
                        child: TextFormField(
                          controller: _dobController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Date of birth',
                            hintText: 'Select your date of birth',
                            suffixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                          onTap: _pickDateOfBirth,
                          validator: (_) {
                            if (_selectedDateOfBirth == null) {
                              return 'Select your date of birth.';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        onChanged: (_) => _validateAfterSubmit(),
                        validator: (value) {
                          if ((value ?? '').length < 6) {
                            return 'Use at least 6 characters.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                        ),
                        onChanged: (_) => _validateAfterSubmit(),
                        validator: (value) {
                          final text = value ?? '';
                          if (text.isEmpty) {
                            return 'Confirm your password.';
                          }
                          if (text != _passwordController.text) {
                            return 'Passwords do not match yet.';
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
                                ? 'Creating your account...'
                                : 'Create account',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _LegalConsentText(
                        termsRecognizer: _termsTapRecognizer,
                        privacyRecognizer: _privacyTapRecognizer,
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
                            : _signUpWithGoogle,
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
                        onPressed: session.isProcessing
                            ? null
                            : _signUpWithGPlus,
                      ),
                      if (_showAppleButton) ...[
                        const SizedBox(height: 10),
                        _SocialAuthButton(
                          label: 'Continue with Apple',
                          icon: const Icon(Icons.apple, size: 20),
                          onPressed: session.isProcessing
                              ? null
                              : _signUpWithApple,
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
    );
  }

  Future<void> _submit() async {
    if (!_submitted) {
      setState(() => _submitted = true);
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final session = context.read<VennuzoSessionController>();
    final navigator = Navigator.of(context);
    try {
      await session.createAccount(
        displayName: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        dateOfBirth: _selectedDateOfBirth!,
        phone: _phoneController.text,
        profileImageBytes: _selectedProfileImageBytes,
        profileImageName: _selectedProfileImage?.name,
      );
      await session.waitForAuthenticatedSession();
      if (!mounted) {
        return;
      }
      navigator.pop(true);
    } on VennuzoAuthFailure catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  bool get _showAppleButton {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
  }

  Future<void> _openLegalUrl(String url, String failureMessage) async {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  Future<void> _signUpWithGoogle() async {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _signUpWithGPlus() async {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _signUpWithApple() async {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _pickProfileImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1400,
      imageQuality: 88,
    );
    if (picked == null || !mounted) {
      return;
    }

    final bytes = await picked.readAsBytes();
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedProfileImage = picked;
      _selectedProfileImageBytes = bytes;
    });
  }

  void _removeProfileImage() {
    setState(() {
      _selectedProfileImage = null;
      _selectedProfileImageBytes = null;
    });
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateOfBirth ?? DateTime(now.year - 21),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _selectedDateOfBirth = DateTime(picked.year, picked.month, picked.day);
      _dobController.text = formatDate(_selectedDateOfBirth!);
    });
    _validateAfterSubmit();
  }

  void _validateAfterSubmit() {
    if (_submitted) {
      _formKey.currentState?.validate();
    }
  }
}

class _ProfileImagePicker extends StatelessWidget {
  const _ProfileImagePicker({
    required this.imageBytes,
    required this.onPick,
    this.onRemove,
  });

  final Uint8List? imageBytes;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      children: [
        CircleAvatar(
          radius: 42,
          backgroundColor: palette.canvas,
          foregroundImage: imageBytes != null ? MemoryImage(imageBytes!) : null,
          child: imageBytes == null
              ? Icon(Icons.person_outline, color: palette.ink, size: 34)
              : null,
        ),
        const SizedBox(height: 12),
        Text(
          'Profile picture (optional)',
          style: context.text.titleLarge?.copyWith(fontSize: 18),
        ),
        const SizedBox(height: 6),
        Text(
          'Choose a photo now or skip it and add one later.',
          textAlign: TextAlign.center,
          style: context.text.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(imageBytes == null ? 'Upload photo' : 'Change photo'),
            ),
            if (onRemove != null)
              TextButton(onPressed: onRemove, child: const Text('Remove')),
          ],
        ),
      ],
    );
  }
}

class _LegalConsentText extends StatelessWidget {
  const _LegalConsentText({
    required this.termsRecognizer,
    required this.privacyRecognizer,
  });

  final TapGestureRecognizer termsRecognizer;
  final TapGestureRecognizer privacyRecognizer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final baseStyle = context.text.bodySmall?.copyWith(color: palette.slate);
    final linkStyle = context.text.bodySmall?.copyWith(
      color: palette.teal,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(text: 'By creating an account you agree to our '),
          TextSpan(
            text: 'Terms of Service',
            style: linkStyle,
            recognizer: termsRecognizer,
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: privacyRecognizer,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
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
          colors: [
            palette.coral.withValues(alpha: 0.60),
            VennuzoTheme.surfaceElevated,
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
