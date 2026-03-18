import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';

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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _dobController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<EventoraSessionController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
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
                title: 'Create your Eventora account',
                body:
                    'Save tickets, RSVP faster, and keep your plans in one place. Add your date of birth now, and include a contact number if you want hosts to have it.',
              ),
              const SizedBox(height: 22),
              Form(
                key: _formKey,
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
                        TextFormField(
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
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
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
                          validator: (value) {
                            if (value != _passwordController.text) {
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
    } on EventoraAuthFailure catch (error) {
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
          colors: [palette.coral, palette.ink],
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
