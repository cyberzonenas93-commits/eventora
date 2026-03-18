import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';
import '../manage/host_access_screen.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<EventoraSessionController>();
    final viewer = session.viewer;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _AccountHero(
            title: viewer.isGuest
                ? 'You are browsing as a guest'
                : viewer.displayName,
            body: viewer.isGuest
                ? 'You can explore public events without signing in. Create an account when you want to save tickets, RSVP faster, or start hosting.'
                : 'Signed in as ${viewer.email ?? 'your Eventora account'}.',
            photoUrl: viewer.photoUrl,
          ),
          const SizedBox(height: 22),
          if (viewer.isGuest) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why it is worth creating an account',
                      style: context.text.titleLarge?.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Accounts let you save tickets, RSVP faster, manage reminders, keep a profile photo, and unlock hosting tools later. Date of birth is collected at signup, while your contact number stays optional.',
                      style: context.text.bodyLarge,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _openSignUp(context),
                        child: const Text('Create account'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _openSignIn(context),
                        child: const Text('I already have an account'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your profile',
                      style: context.text.titleLarge?.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 16),
                    _DetailRow(
                      label: 'Display name',
                      value: viewer.displayName,
                    ),
                    _DetailRow(
                      label: 'Email',
                      value: viewer.email ?? 'Not available',
                    ),
                    _DetailRow(
                      label: 'DOB',
                      value: viewer.dateOfBirth != null
                          ? formatDate(viewer.dateOfBirth!)
                          : 'Not provided',
                    ),
                    _DetailRow(
                      label: 'Contact',
                      value: viewer.phone?.isNotEmpty == true
                          ? viewer.phone!
                          : 'Not provided',
                    ),
                    _DetailRow(
                      label: 'App view',
                      value: viewer.isAdminWorkspace
                          ? 'Admin console'
                          : 'Eventora app',
                    ),
                    if (viewer.roles.isNotEmpty)
                      _DetailRow(
                        label: 'Roles',
                        value: viewer.roles.join(', '),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (session.canChooseWorkspace)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Workspace switcher',
                        style: context.text.titleLarge?.copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'This account can open both the Eventora app and the admin console. Switch views without signing out.',
                        style: context.text.bodyMedium?.copyWith(
                          color: context.palette.slate,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            session.openWorkspaceChooser();
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.swap_horiz_outlined),
                          label: const Text('Switch view'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Want to host events?',
                      style: context.text.titleLarge?.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 10),
                      Text(
                        viewer.hasOrganizerAccess
                          ? 'Your account can open the full host workspace and manage live event operations.'
                          : 'Finish your host access setup in the app so we can unlock the full publishing and operations tools.',
                        style: context.text.bodyMedium?.copyWith(
                          color: context.palette.slate,
                        ),
                    ),
                    const SizedBox(height: 14),
                    _DetailRow(
                      label: 'Status',
                      value: viewer.organizerStatusLabel,
                    ),
                    if ((viewer.organizerReviewNotes ?? '').isNotEmpty)
                      _DetailRow(
                        label: 'Latest note',
                        value: viewer.organizerReviewNotes!,
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openHostAccess(context),
                        icon: const Icon(Icons.storefront_outlined),
                        label: Text(
                          viewer.hasOrganizerAccess
                              ? 'Open host access'
                              : viewer.hasPendingOrganizerApplication
                              ? 'Review host status'
                              : 'Start host setup',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications',
                      style: context.text.titleLarge?.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Choose how Eventora keeps you updated. Promotional messages stay off unless you opt in.',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.palette.slate,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: viewer.notificationPrefs.pushEnabled,
                      onChanged: session.isProcessing
                          ? null
                          : (value) =>
                                _updatePrefs(context, pushEnabled: value),
                      title: const Text('Push notifications'),
                      subtitle: const Text(
                        'Ticket updates, reminders, and event alerts on this device.',
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: viewer.notificationPrefs.smsEnabled,
                      onChanged: session.isProcessing
                          ? null
                          : (value) => _updatePrefs(context, smsEnabled: value),
                      title: const Text('SMS updates'),
                      subtitle: const Text(
                        'Transactional event texts if you add a phone number through RSVP or checkout.',
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: viewer.notificationPrefs.marketingOptIn,
                      onChanged: session.isProcessing
                          ? null
                          : (value) =>
                                _updatePrefs(context, marketingOptIn: value),
                      title: const Text('Promotional campaigns'),
                      subtitle: const Text(
                        'Turn this on only if you want hosts to send you event promos and launch updates.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account actions',
                      style: context.text.titleLarge?.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: session.isProcessing
                            ? null
                            : () => _signOut(context),
                        child: const Text('Sign out'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: session.isProcessing
                            ? null
                            : () => _confirmDelete(context),
                        style: FilledButton.styleFrom(
                          foregroundColor: context.palette.coral,
                        ),
                        child: Text(
                          session.isProcessing
                              ? 'Processing...'
                              : 'Delete account',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Deleting your account removes your profile from the app. You can always create a new one later.',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.palette.slate,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Safety and support',
                    style: context.text.titleLarge?.copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You can browse as a guest, report listings that feel unsafe, and share only the details needed for tickets, reminders, and account security.',
                    style: context.text.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await context.read<EventoraSessionController>().signOut();
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You are signed out.')));
    } on EventoraAuthFailure catch (error) {
      _showMessage(context, error.message);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final passwordController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently removes your Eventora account profile. Enter your current password to confirm.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(passwordController.text),
              child: const Text('Delete account'),
            ),
          ],
        );
      },
    );
    passwordController.dispose();

    if (!context.mounted || password == null || password.trim().isEmpty) {
      return;
    }

    try {
      await context.read<EventoraSessionController>().deleteAccount(
        currentPassword: password.trim(),
      );
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your Eventora account was deleted.')),
      );
    } on EventoraAuthFailure catch (error) {
      _showMessage(context, error.message);
    }
  }

  Future<void> _openSignIn(BuildContext context) async {
    final signedIn = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const SignInScreen()));
    if (signedIn == true && context.mounted) {
      _showMessage(context, 'You are signed in and ready to go.');
    }
  }

  Future<void> _openSignUp(BuildContext context) async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const SignUpScreen()));
    if (created == true && context.mounted) {
      _showMessage(context, 'Your Eventora account is ready to use.');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openHostAccess(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HostAccessScreen()));
  }

  Future<void> _updatePrefs(
    BuildContext context, {
    bool? pushEnabled,
    bool? smsEnabled,
    bool? marketingOptIn,
  }) async {
    try {
      await context.read<EventoraSessionController>().updateNotificationPrefs(
        pushEnabled: pushEnabled,
        smsEnabled: smsEnabled,
        marketingOptIn: marketingOptIn,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification preferences updated.')),
      );
    } on EventoraAuthFailure catch (error) {
      _showMessage(context, error.message);
    }
  }
}

class _AccountHero extends StatelessWidget {
  const _AccountHero({required this.title, required this.body, this.photoUrl});

  final String title;
  final String body;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: LinearGradient(
          colors: [palette.ink, palette.teal, palette.gold],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -28,
            right: -8,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                foregroundImage: photoUrl != null
                    ? NetworkImage(photoUrl!)
                    : null,
                child: photoUrl == null
                    ? const Icon(
                        Icons.person_outline,
                        color: Colors.white,
                        size: 30,
                      )
                    : null,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: context.text.headlineSmall?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: context.text.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _HeroBadge(label: 'Tickets'),
                  _HeroBadge(label: 'RSVPs'),
                  _HeroBadge(label: 'Hosting tools'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: context.text.bodyMedium?.copyWith(
                color: context.palette.slate,
              ),
            ),
          ),
          Expanded(child: Text(value, style: context.text.bodyLarge)),
        ],
      ),
    );
  }
}
