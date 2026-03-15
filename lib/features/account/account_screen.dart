import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/portal_links.dart';
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
            title: viewer.isGuest ? 'Guest access is on' : viewer.displayName,
            body: viewer.isGuest
                ? 'You can browse public events without creating an account. Sign in only when you want to RSVP, buy tickets, manage events, or launch campaigns.'
                : 'Signed in with ${viewer.email ?? 'your Eventora account'}.',
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
                      'Why create an account?',
                      style: context.text.titleLarge?.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Accounts unlock RSVPs, ticket checkout, admin access, and organizer applications. Phone remains optional at signup.',
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
                        child: const Text('Sign in'),
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
                      'Profile',
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
                      label: 'Phone',
                      value: viewer.phone?.isNotEmpty == true
                          ? viewer.phone!
                          : 'Not provided',
                    ),
                    _DetailRow(
                      label: 'Workspace',
                      value: viewer.isAdminWorkspace
                          ? 'Admin console'
                          : 'Customer app',
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
                        'This account can open both faces of Eventora. Switch without signing out when you want to move between the customer app and the admin console.',
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
                          label: const Text('Choose workspace'),
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
                      'Organizer access',
                      style: context.text.titleLarge?.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      viewer.hasOrganizerAccess
                          ? 'This account is approved for Eventora Studio and can manage organizer tools.'
                          : 'Organizer onboarding and verification now live in Eventora Studio so superadmins can review and approve teams before they publish.',
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
                        label: 'Review note',
                        value: viewer.organizerReviewNotes!,
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openOrganizerPortal(context),
                        icon: const Icon(Icons.open_in_browser_outlined),
                        label: Text(
                          viewer.hasOrganizerAccess
                              ? 'Open Eventora Studio'
                              : viewer.hasPendingOrganizerApplication
                              ? 'Continue application in Studio'
                              : 'Apply in Eventora Studio',
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
                      'Push and SMS alerts stay optional. Marketing campaigns only reach attendees who opt in.',
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
                        'Opt in before organizers can reach you with broadcast event campaigns.',
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
                      'Account deletion is handled in-app so App Store and Play review can verify it directly.',
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
                    'Eventora keeps guest browsing open, collects only the minimum signup data required, and adds reporting tools for organizer-created content.',
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
      ).showSnackBar(const SnackBar(content: Text('Signed out of Eventora.')));
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

  void _openSignIn(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SignInScreen()));
  }

  void _openSignUp(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SignUpScreen()));
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openOrganizerPortal(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(eventoraStudioUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      _showMessage(
        context,
        'Could not open Eventora Studio right now. Try again in a browser.',
      );
    }
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
  const _AccountHero({required this.title, required this.body});

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
          colors: [palette.ink, palette.gold],
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
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
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
