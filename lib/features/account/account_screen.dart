import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/event_models.dart';
import '../manage/host_access_screen.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';
import 'support_chat_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    final viewer = session.viewer;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _AccountHero(
            title: viewer.isGuest ? 'Guest mode' : viewer.displayName,
            body: viewer.isGuest
                ? null
                : viewer.email ?? 'Your Vennuzo account',
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
                      'Create an account',
                      style: context.text.titleLarge?.copyWith(fontSize: 20),
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
                          ? viewer.hasSuperAdminAccess
                                ? 'Superadmin console'
                                : 'Admin console'
                          : viewer.isOrganizerWorkspace
                          ? 'Organizer portal'
                          : 'Vennuzo app',
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
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: viewer.notificationPrefs.pushEnabled,
                      onChanged: session.isProcessing
                          ? null
                          : (value) =>
                                _updatePrefs(context, pushEnabled: value),
                      title: const Text('Push notifications'),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: viewer.notificationPrefs.smsEnabled,
                      onChanged: session.isProcessing
                          ? null
                          : (value) => _updatePrefs(context, smsEnabled: value),
                      title: const Text('SMS updates'),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: viewer.notificationPrefs.marketingOptIn,
                      onChanged: session.isProcessing
                          ? null
                          : (value) =>
                                _updatePrefs(context, marketingOptIn: value),
                      title: const Text('Promotional campaigns'),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: viewer.notificationPrefs.promotionalPushEnabled,
                      onChanged:
                          session.isProcessing ||
                              !viewer.notificationPrefs.marketingOptIn
                          ? null
                          : (value) => _updatePrefs(
                              context,
                              promotionalPushEnabled: value,
                            ),
                      title: const Text('Promotional push alerts'),
                      subtitle: const Text(
                        'Only for event types you choose below.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Promotional event types',
                      style: context.text.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: EventTaxonomy.categories.map((category) {
                        final selected = viewer
                            .notificationPrefs
                            .promotionalEventTypes
                            .map(EventTaxonomy.canonicalCategoryId)
                            .contains(category.id);
                        return ChoiceChip(
                          label: Text(category.shortLabel),
                          selected: selected,
                          onSelected:
                              session.isProcessing ||
                                  !viewer.notificationPrefs.marketingOptIn
                              ? null
                              : (_) {
                                  final current = viewer
                                      .notificationPrefs
                                      .promotionalEventTypes
                                      .map(EventTaxonomy.canonicalCategoryId)
                                      .toSet();
                                  if (selected) {
                                    current.remove(category.id);
                                  } else {
                                    current.add(category.id);
                                  }
                                  _updatePrefs(
                                    context,
                                    promotionalEventTypes: current.toList()
                                      ..sort(),
                                  );
                                },
                        );
                      }).toList(),
                    ),
                    if (viewer.notificationPrefs.promotionalEventTypes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'No type selected means you can receive opted-in promotions for any event type in audiences you joined.',
                          style: context.text.bodySmall,
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
                          backgroundColor: context.palette.coral,
                          foregroundColor: const Color(0xFF031018),
                          disabledBackgroundColor: context.palette.coral
                              .withValues(alpha: 0.45),
                          disabledForegroundColor: const Color(
                            0xFF031018,
                          ).withValues(alpha: 0.70),
                          textStyle: context.text.labelLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        child: Text(
                          session.isProcessing
                              ? 'Processing...'
                              : 'Delete account',
                        ),
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
                    'Get help with account access, payments, event safety, and suspicious listings.',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.palette.slate,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SupportActionTile(
                    icon: Icons.shield_outlined,
                    title: 'Safety tips',
                    subtitle: 'How to spot and report risky events',
                    onTap: () => _openSafetyTips(context),
                  ),
                  const SizedBox(height: 10),
                  _SupportActionTile(
                    icon: Icons.support_agent_rounded,
                    title: 'Chat with support',
                    subtitle: 'Create a secure in-app support ticket',
                    onTap: () => _openSupportChat(context),
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
      await context.read<VennuzoSessionController>().signOut();
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You are signed out.')));
    } on VennuzoAuthFailure catch (error) {
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
                'This permanently removes your Vennuzo account profile. Enter your current password to confirm.',
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
      await context.read<VennuzoSessionController>().deleteAccount(
        currentPassword: password.trim(),
      );
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your Vennuzo account was deleted.')),
      );
    } on VennuzoAuthFailure catch (error) {
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
      _showMessage(context, 'Your Vennuzo account is ready to use.');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openSafetyTips(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Safety tips',
                style: sheetContext.text.titleLarge?.copyWith(fontSize: 22),
              ),
              const SizedBox(height: 14),
              const _SafetyTip(
                icon: Icons.verified_outlined,
                text:
                    'Check the venue, organizer, date, and ticket price before paying.',
              ),
              const _SafetyTip(
                icon: Icons.payment_outlined,
                text:
                    'Use Vennuzo checkout or trusted payment links for ticketed events.',
              ),
              const _SafetyTip(
                icon: Icons.flag_outlined,
                text:
                    'Use Report event on the event page if a listing looks unsafe.',
              ),
            ],
          ),
        );
      },
    );
  }

  void _openHostAccess(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HostAccessScreen()));
  }

  void _openSupportChat(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SupportChatScreen()));
  }

  Future<void> _updatePrefs(
    BuildContext context, {
    bool? pushEnabled,
    bool? smsEnabled,
    bool? marketingOptIn,
    bool? promotionalPushEnabled,
    List<String>? promotionalEventTypes,
  }) async {
    try {
      await context.read<VennuzoSessionController>().updateNotificationPrefs(
        pushEnabled: pushEnabled,
        smsEnabled: smsEnabled,
        marketingOptIn: marketingOptIn,
        promotionalPushEnabled: promotionalPushEnabled,
        promotionalEventTypes: promotionalEventTypes,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification preferences updated.')),
      );
    } on VennuzoAuthFailure catch (error) {
      _showMessage(context, error.message);
    }
  }
}

class _AccountHero extends StatelessWidget {
  const _AccountHero({required this.title, this.body, this.photoUrl});

  final String title;
  final String? body;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: LinearGradient(
          colors: [
            VennuzoTheme.surface,
            VennuzoTheme.surfaceBright,
            palette.gold,
          ],
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
                    ? CachedNetworkImageProvider(photoUrl!)
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.headlineSmall?.copyWith(
                  color: Colors.white,
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: 12),
                Text(
                  body!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _HeroBadge(label: 'Tickets'),
                  _HeroBadge(label: 'Hosting'),
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

class _SupportActionTile extends StatelessWidget {
  const _SupportActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      label: title,
      hint: subtitle,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.canvas,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: palette.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: palette.teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: context.text.bodyMedium?.copyWith(
                        color: palette.slate,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.slate),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafetyTip extends StatelessWidget {
  const _SafetyTip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.palette.teal, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: context.text.bodyLarge)),
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
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}
