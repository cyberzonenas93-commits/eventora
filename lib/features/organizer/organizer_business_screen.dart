import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../data/services/vennuzo_organizer_application_service.dart';
import '../../data/services/vennuzo_payment_service.dart';
import '../../domain/models/account_models.dart';
import '../../domain/models/creative_service_models.dart';
import '../../domain/models/ticket_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/section_heading.dart';
import '../creative/creative_services_screen.dart';
import '../manage/host_access_screen.dart';

class OrganizerBusinessScreen extends StatefulWidget {
  const OrganizerBusinessScreen({super.key});

  @override
  State<OrganizerBusinessScreen> createState() =>
      _OrganizerBusinessScreenState();
}

class _OrganizerBusinessScreenState extends State<OrganizerBusinessScreen> {
  String? _loadedOrganizationId;
  WalletBalance? _wallet;
  VennuzoOrganizerApplicationDraft? _application;
  bool _loading = false;
  String? _walletError;
  String? _applicationError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewer = context.read<VennuzoSessionController>().viewer;
    final organizationId = _organizationIdFor(viewer);
    if (organizationId != null && organizationId != _loadedOrganizationId) {
      _loadedOrganizationId = organizationId;
      unawaited(_loadBusinessData(organizationId, viewer));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    final repository = context.watch<VennuzoRepository>();
    final viewer = session.viewer;
    final organizationId = _organizationIdFor(viewer);
    final contacts = _buildContacts(repository);
    final totalRevenue = repository.managedEvents.fold<double>(
      0,
      (sum, event) => sum + repository.revenueForEvent(event.id),
    );
    final paidOrders = repository.orders
        .where((order) => order.status == TicketOrderStatus.paid)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      children: [
        _BusinessHero(
          revenue: totalRevenue,
          contactCount: contacts.length,
          wallet: _wallet,
          loading: _loading,
        ),
        const SizedBox(height: 22),
        if (!viewer.hasOrganizerAccess)
          EmptyStateCard(
            title: 'Organizer access required',
            body: 'Business tools are available after host access is approved.',
            icon: Icons.storefront_outlined,
            actionLabel: 'Open host access',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HostAccessScreen()),
            ),
          )
        else ...[
          _WalletSection(
            wallet: _wallet,
            organizationId: organizationId,
            error: _walletError,
            onRefresh: organizationId == null
                ? null
                : () => _loadBusinessData(organizationId, viewer),
            onOpenCreative: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CreativeServicesScreen(),
              ),
            ),
          ),
          const SizedBox(height: 28),
          _CrmSection(
            contacts: contacts,
            totalOrders: paidOrders,
            totalSpend: totalRevenue,
          ),
          const SizedBox(height: 28),
          _PayoutSection(
            application: _application,
            error: _applicationError,
            totalRevenue: totalRevenue,
          ),
          const SizedBox(height: 28),
          _PartnersSection(
            campaigns: repository.campaigns.length,
            orders: paidOrders,
            revenue: totalRevenue,
          ),
        ],
      ],
    );
  }

  Future<void> _loadBusinessData(
    String organizationId,
    VennuzoViewer viewer,
  ) async {
    setState(() {
      _loading = true;
      _walletError = null;
      _applicationError = null;
    });

    WalletBalance? wallet;
    VennuzoOrganizerApplicationDraft? application;
    String? walletError;
    String? applicationError;

    try {
      wallet = await VennuzoPaymentService.getWalletBalance(
        organizationId: organizationId,
      );
    } catch (error) {
      walletError = 'Wallet balance is unavailable right now.';
    }

    final uid = viewer.uid;
    if (uid != null && uid.isNotEmpty) {
      try {
        application = await VennuzoOrganizerApplicationService.instance
            .loadDraft(uid, viewer: viewer);
      } catch (error) {
        applicationError = 'Payout profile is unavailable right now.';
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _wallet = wallet;
      _application = application;
      _walletError = walletError;
      _applicationError = applicationError;
      _loading = false;
    });
  }

  String? _organizationIdFor(VennuzoViewer viewer) {
    final explicit = viewer.defaultOrganizationId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final uid = viewer.uid?.trim();
    if (viewer.hasOrganizerAccess && uid != null && uid.isNotEmpty) {
      return 'org_$uid';
    }
    return null;
  }

  List<_CrmContact> _buildContacts(VennuzoRepository repository) {
    final contacts = <String, _CrmContact>{};
    for (final rsvp in repository.rsvps) {
      final key = _contactKey(name: rsvp.name, phone: rsvp.phone, email: '');
      final existing = contacts[key] ?? _CrmContact(name: rsvp.name);
      contacts[key] = existing.copyWith(
        phone: rsvp.phone,
        rsvpCount: existing.rsvpCount + 1,
      );
    }
    for (final order in repository.orders) {
      final key = _contactKey(
        name: order.buyerName,
        phone: order.buyerPhone,
        email: order.buyerEmail,
      );
      final existing = contacts[key] ?? _CrmContact(name: order.buyerName);
      contacts[key] = existing.copyWith(
        phone: order.buyerPhone,
        email: order.buyerEmail,
        orderCount: existing.orderCount + 1,
        spend:
            existing.spend +
            (order.status == TicketOrderStatus.paid ? order.totalAmount : 0),
      );
    }
    final values = contacts.values.toList()
      ..sort((a, b) => b.spend.compareTo(a.spend));
    return values;
  }

  String _contactKey({
    required String name,
    required String phone,
    required String email,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isNotEmpty) return 'email:$normalizedEmail';
    final normalizedPhone = phone.trim();
    if (normalizedPhone.isNotEmpty) return 'phone:$normalizedPhone';
    return 'name:${name.trim().toLowerCase()}';
  }
}

class _BusinessHero extends StatelessWidget {
  const _BusinessHero({
    required this.revenue,
    required this.contactCount,
    required this.wallet,
    required this.loading,
  });

  final double revenue;
  final int contactCount;
  final WalletBalance? wallet;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [
            VennuzoTheme.surface,
            VennuzoTheme.surfaceBright,
            VennuzoTheme.primaryStart,
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
            'Business tools',
            style: context.text.bodyLarge?.copyWith(
              color: VennuzoTheme.primaryStart,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Wallet, CRM, payouts, and partners.',
            style: context.text.headlineSmall?.copyWith(
              color: VennuzoTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${formatMoney(revenue)} revenue, $contactCount contacts, ${loading ? 'wallet loading' : formatMoney(wallet?.availableBalance ?? 0)} wallet balance.',
            style: context.text.bodyLarge?.copyWith(
              color: VennuzoTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletSection extends StatelessWidget {
  const _WalletSection({
    required this.wallet,
    required this.organizationId,
    required this.error,
    required this.onRefresh,
    required this.onOpenCreative,
  });

  final WalletBalance? wallet;
  final String? organizationId;
  final String? error;
  final VoidCallback? onRefresh;
  final VoidCallback onOpenCreative;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'Campaign wallet',
          subtitle:
              'Paid push, SMS, flyer generation, and table-package flyers use this wallet.',
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Pill(
                      label:
                          'Available ${formatMoney(wallet?.availableBalance ?? 0)}',
                    ),
                    _Pill(
                      label: 'Held ${formatMoney(wallet?.heldBalance ?? 0)}',
                    ),
                    if (organizationId != null) _Pill(label: organizationId!),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: context.text.bodyMedium),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_outlined),
                      label: const Text('Refresh'),
                    ),
                    ElevatedButton.icon(
                      onPressed: onOpenCreative,
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('Top up / use wallet'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CrmSection extends StatelessWidget {
  const _CrmSection({
    required this.contacts,
    required this.totalOrders,
    required this.totalSpend,
  });

  final List<_CrmContact> contacts;
  final int totalOrders;
  final double totalSpend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'Contacts / CRM',
          subtitle:
              'CRM for people who RSVP, buy tickets, or appear in imported opt-in audiences.',
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Pill(label: '${contacts.length} contacts'),
                    _Pill(label: '$totalOrders paid orders'),
                    _Pill(label: '${formatMoney(totalSpend)} spend'),
                    const _Pill(label: 'Owned audience'),
                  ],
                ),
                const SizedBox(height: 16),
                if (contacts.isEmpty)
                  Text(
                    'RSVP guests, ticket buyers, and uploaded opt-in contacts will appear here.',
                    style: context.text.bodyMedium,
                  )
                else
                  ...contacts
                      .take(5)
                      .map(
                        (contact) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ContactRow(contact: contact),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PayoutSection extends StatelessWidget {
  const _PayoutSection({
    required this.application,
    required this.error,
    required this.totalRevenue,
  });

  final VennuzoOrganizerApplicationDraft? application;
  final String? error;
  final double totalRevenue;

  @override
  Widget build(BuildContext context) {
    final destination = _destinationLabel(application);
    final ready =
        application?.agreedToPayoutTerms == true &&
        destination != 'Not set yet';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'Payments and payouts',
          subtitle:
              'Payout readiness, destination, lifetime gross event revenue, and payout setup.',
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Pill(label: ready ? 'Payout ready' : 'Setup needed'),
                    _Pill(label: 'Gross ${formatMoney(totalRevenue)}'),
                    _Pill(label: destination),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: context.text.bodyMedium),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HostAccessScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('Edit payout details'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _destinationLabel(VennuzoOrganizerApplicationDraft? draft) {
    if (draft == null) return 'Not set yet';
    if (draft.payoutMethod == 'bank') {
      final parts = [
        draft.bankName,
        draft.accountName,
        draft.accountNumber,
      ].where((value) => value.trim().isNotEmpty).toList();
      return parts.isEmpty ? 'Not set yet' : parts.join(' • ');
    }
    final parts = [
      draft.network,
      draft.payoutPhone,
    ].where((value) => value.trim().isNotEmpty).toList();
    return parts.isEmpty ? 'Not set yet' : parts.join(' • ');
  }
}

class _PartnersSection extends StatelessWidget {
  const _PartnersSection({
    required this.campaigns,
    required this.orders,
    required this.revenue,
  });

  final int campaigns;
  final int orders;
  final double revenue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'Partners / referrals',
          subtitle:
              'Promoter and affiliate tracking for clicks, orders, revenue, and payouts.',
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Pill(label: '$campaigns tracked campaigns'),
                    _Pill(label: '$orders paid orders'),
                    _Pill(label: formatMoney(revenue)),
                    const _Pill(label: 'Usage based'),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openStudio('/studio/promoters'),
                    icon: const Icon(Icons.open_in_new_outlined),
                    label: const Text('Open partner desk'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact});

  final _CrmContact contact;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (contact.phone.isNotEmpty) contact.phone,
      if (contact.email.isNotEmpty) contact.email,
      '${contact.rsvpCount} RSVPs',
      '${contact.orderCount} orders',
    ].join(' • ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name.isEmpty ? 'Unnamed contact' : contact.name,
                  style: context.text.bodyLarge?.copyWith(
                    color: context.palette.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: context.palette.slate,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(contact.spend),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodyMedium?.copyWith(
              color: context.palette.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: context.palette.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CrmContact {
  const _CrmContact({
    required this.name,
    this.phone = '',
    this.email = '',
    this.rsvpCount = 0,
    this.orderCount = 0,
    this.spend = 0,
  });

  final String name;
  final String phone;
  final String email;
  final int rsvpCount;
  final int orderCount;
  final double spend;

  _CrmContact copyWith({
    String? phone,
    String? email,
    int? rsvpCount,
    int? orderCount,
    double? spend,
  }) {
    return _CrmContact(
      name: name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      rsvpCount: rsvpCount ?? this.rsvpCount,
      orderCount: orderCount ?? this.orderCount,
      spend: spend ?? this.spend,
    );
  }
}

Future<void> _openStudio(String path) async {
  final uri = Uri.https('studio.vennuzo.com', path);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
