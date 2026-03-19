import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';

class AdminOrganizerApprovalsScreen extends StatefulWidget {
  const AdminOrganizerApprovalsScreen({super.key});

  @override
  State<AdminOrganizerApprovalsScreen> createState() =>
      _AdminOrganizerApprovalsScreenState();
}

class _AdminOrganizerApprovalsScreenState
    extends State<AdminOrganizerApprovalsScreen> {
  String _filter = 'submitted';
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    final isSuperAdmin = session.hasSuperAdminAccess;

    return Scaffold(
      appBar: AppBar(title: const Text('Organizer approvals')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _ApprovalHero(isSuperAdmin: isSuperAdmin),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in const [
                'submitted',
                'under_review',
                'approved',
                'rejected',
                'all',
              ])
                ChoiceChip(
                  label: Text(option == 'all'
                      ? 'All'
                      : option.replaceAll('_', ' ')),
                  selected: _filter == option,
                  onSelected: (_) => setState(() => _filter = option),
                ),
            ],
          ),
          const SizedBox(height: 18),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('organizer_applications')
                .orderBy('updatedAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (snapshot.hasError) {
                return _MessageCard(
                  title: 'Could not load organizer applications',
                  body:
                      'Check Firestore permissions and make sure organizer applications exist in the project.',
                  icon: Icons.cloud_off_outlined,
                );
              }

              final docs = snapshot.data?.docs ?? const [];
              final filtered = docs.where((doc) {
                if (_filter == 'all') {
                  return true;
                }
                return (doc.data()['status'] as String?) == _filter;
              }).toList();

              if (filtered.isEmpty) {
                return _MessageCard(
                  title: 'No organizer applications here',
                  body:
                      'When organizers submit through Vennuzo Studio, they will appear in this queue for review.',
                  icon: Icons.inbox_outlined,
                );
              }

              return Column(
                children: [
                  for (final doc in filtered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ApplicationCard(
                        data: doc.data(),
                        isBusy: _isSubmitting,
                        canReview: isSuperAdmin,
                        onDecision: (decision) =>
                            _reviewApplication(doc.id, decision),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _reviewApplication(String applicationId, String decision) async {
    final noteController = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            switch (decision) {
              'approved' => 'Approve organizer?',
              'rejected' => 'Reject organizer?',
              _ => 'Move application into review?',
            },
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                decision == 'approved'
                    ? 'This grants organizer access and provisions the organization workspace.'
                    : decision == 'rejected'
                    ? 'Add a clear note so the organizer knows what to fix.'
                    : 'This marks the application as under review without approving it yet.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Review note',
                ),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                noteController.text.trim(),
              ),
              child: Text(
                switch (decision) {
                  'approved' => 'Approve',
                  'rejected' => 'Reject',
                  _ => 'Start review',
                },
              ),
            ),
          ],
        );
      },
    );
    noteController.dispose();

    if (!mounted || note == null) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('reviewOrganizerApplication')
          .call(<String, Object?>{
            'applicationId': applicationId,
            'decision': decision,
            'reviewNotes': note,
          });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Application updated: $decision')),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message ?? 'Could not review this organizer application.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _ApprovalHero extends StatelessWidget {
  const _ApprovalHero({required this.isSuperAdmin});

  final bool isSuperAdmin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withValues(alpha: 0.9),
        border: Border.all(color: const Color(0x1410212A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Organizer approval queue',
            style: context.text.titleLarge?.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 12),
          Text(
            isSuperAdmin
                ? 'Review Vennuzo Studio applications, mark them under review, and approve the teams that should publish and sell on the platform.'
                : 'This queue is visible, but only superadmins can approve or reject organizer applications.',
            style: context.text.bodyLarge?.copyWith(
              color: context.palette.slate,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.data,
    required this.canReview,
    required this.isBusy,
    required this.onDecision,
  });

  final Map<String, dynamic> data;
  final bool canReview;
  final bool isBusy;
  final Future<void> Function(String decision) onDecision;

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] as String?) ?? 'draft';
    final reviewedAt = data['reviewedAt'];
    final submittedAt = data['submittedAt'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (data['organizerName'] as String?) ?? 'Unnamed organizer',
                    style: context.text.titleLarge?.copyWith(fontSize: 20),
                  ),
                ),
                _StatusPill(status: status),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              (data['contactPerson'] as String?) ?? 'No contact person',
              style: context.text.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text(
              [
                data['email'] as String?,
                data['phone'] as String?,
                data['businessType'] as String?,
              ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' • '),
              style: context.text.bodyMedium?.copyWith(
                color: context.palette.slate,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              (data['businessAddress'] as String?)?.trim().isNotEmpty == true
                  ? data['businessAddress'] as String
                  : 'No business address provided yet.',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  label: 'Submitted',
                  value: _formatTimestamp(submittedAt),
                ),
                _InfoChip(
                  label: 'Reviewed',
                  value: _formatTimestamp(reviewedAt),
                ),
                if ((data['settlementPreference'] as String?)?.isNotEmpty == true)
                  _InfoChip(
                    label: 'Settlement',
                    value: data['settlementPreference'] as String,
                  ),
              ],
            ),
            if ((data['reviewNotes'] as String?)?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 14),
              Text(
                'Review note',
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                data['reviewNotes'] as String,
                style: context.text.bodyMedium?.copyWith(
                  color: context.palette.slate,
                ),
              ),
            ],
            if (canReview) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: isBusy ? null : () => onDecision('under_review'),
                    child: const Text('Under review'),
                  ),
                  FilledButton.tonal(
                    onPressed: isBusy ? null : () => onDecision('rejected'),
                    child: const Text('Reject'),
                  ),
                  FilledButton(
                    onPressed: isBusy ? null : () => onDecision('approved'),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic value) {
    if (value is! Timestamp) {
      return 'Not yet';
    }
    final date = value.toDate();
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' => context.palette.teal,
      'rejected' => context.palette.coral,
      'under_review' => context.palette.gold,
      _ => context.palette.ink,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: context.text.bodyMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$label: $value',
        style: context.text.bodySmall?.copyWith(
          color: context.palette.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 32, color: context.palette.slate),
            const SizedBox(height: 12),
            Text(title, style: context.text.titleLarge),
            const SizedBox(height: 8),
            Text(body, style: context.text.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
