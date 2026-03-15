import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/eventora_repository.dart';
import '../../domain/models/promotion_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_heading.dart';
import '../account/auth_prompt_sheet.dart';
import 'campaign_composer_sheet.dart';

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key});

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  PromotionStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<EventoraRepository>();
    final session = context.watch<EventoraSessionController>();
    final campaigns = repository.campaigns;
    final filtered = _filter == null
        ? campaigns
        : campaigns.where((campaign) => campaign.status == _filter).toList();
    final liveCount = campaigns.where((campaign) => campaign.status == PromotionStatus.live).length;
    final scheduledCount = campaigns.where((campaign) => campaign.status == PromotionStatus.scheduled).length;
    final totalReach = campaigns.fold<int>(
      0,
      (sum, campaign) => sum + campaign.pushAudience + campaign.smsAudience,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        _PromotionsHero(
          onLaunch: () => session.isGuest ? _promptForAccess(context) : _launchCampaign(context),
          isGuest: session.isGuest,
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            MetricTile(
              label: 'Total campaigns',
              value: '${campaigns.length}',
              icon: Icons.campaign_outlined,
            ),
            MetricTile(
              label: 'Live right now',
              value: '$liveCount',
              icon: Icons.wifi_tethering_outlined,
              highlight: context.palette.coral,
            ),
            MetricTile(
              label: 'Combined audience',
              value: '$totalReach',
              icon: Icons.groups_2_outlined,
              highlight: context.palette.teal,
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Audience routes',
          subtitle: 'Mix push, SMS, share links, and featured placement around each event.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _FilterChip(
              label: 'All',
              selected: _filter == null,
              onTap: () => setState(() => _filter = null),
            ),
            _FilterChip(
              label: 'Live',
              selected: _filter == PromotionStatus.live,
              onTap: () => setState(() => _filter = PromotionStatus.live),
            ),
            _FilterChip(
              label: 'Scheduled',
              selected: _filter == PromotionStatus.scheduled,
              onTap: () => setState(() => _filter = PromotionStatus.scheduled),
            ),
            _FilterChip(
              label: 'Completed',
              selected: _filter == PromotionStatus.completed,
              onTap: () => setState(() => _filter = PromotionStatus.completed),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _EventReachSection(),
        const SizedBox(height: 24),
        SectionHeading(
          title: 'Campaign history',
          subtitle: 'Every promotion is event-linked, which makes auditing reach and sales easier later.',
        ),
        const SizedBox(height: 14),
        if (session.isGuest)
          EmptyStateCard(
            title: 'Promotion tools need an account',
            body: 'Sign in to launch push, SMS, share-link, and featured campaigns around your events.',
            icon: Icons.outbound_outlined,
            actionLabel: 'Create account',
            onAction: () => _promptForAccess(context),
          )
        else if (filtered.isEmpty)
          EmptyStateCard(
            title: 'No campaigns match this view',
            body: scheduledCount == 0
                ? 'Launch a campaign to start building push and SMS audiences around your events.'
                : 'Try another status filter or create a new campaign.',
            icon: Icons.outbound_outlined,
            actionLabel: 'Launch campaign',
            onAction: () => _launchCampaign(context),
          )
        else
          ...filtered.map(
            (campaign) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _CampaignCard(campaign: campaign),
            ),
          ),
      ],
    );
  }

  Future<void> _launchCampaign(BuildContext context) async {
    final campaign = await showCampaignComposerSheet(context);
    if (campaign != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Campaign "${campaign.name}" is ready.')),
      );
    }
  }

  void _promptForAccess(BuildContext context) {
    showAuthPromptSheet(
      context,
      title: 'Campaign launch is account-only',
      body: 'Create an Eventora account to run push, SMS, featured, and share-link promotion flows.',
    );
  }
}

class _PromotionsHero extends StatelessWidget {
  const _PromotionsHero({
    required this.onLaunch,
    required this.isGuest,
  });

  final VoidCallback onLaunch;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [palette.teal, palette.ink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Promotion engine',
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.84),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isGuest
                ? 'Browse the campaign architecture first, then sign in to launch real promotion flows.'
                : 'Turn events into campaigns, not one-off posts.',
            style: context.text.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            isGuest
                ? 'Guest access keeps Eventora reviewable without exposing organizer-only growth tooling.'
                : 'Launch a campaign that combines share links, push, SMS, and featured discovery placement.',
            style: context.text.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.86)),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onLaunch,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: palette.ink,
            ),
            child: Text(isGuest ? 'Create account' : 'Launch campaign'),
          ),
        ],
      ),
    );
  }
}

class _EventReachSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repository = context.watch<EventoraRepository>();
    final events = repository.managedEvents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'Event reach by source',
          subtitle: 'The same event model powers push estimates, SMS audiences, and share-link readiness.',
        ),
        const SizedBox(height: 14),
        if (events.isEmpty)
          const SizedBox.shrink()
        else
          ...events.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title, style: context.text.titleLarge?.copyWith(fontSize: 20)),
                      const SizedBox(height: 6),
                      Text(
                        '${repository.pushAudienceFor(event.id)} push • ${repository.smsAudienceFor(event.id)} SMS',
                        style: context.text.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _MiniReachPill(label: '${event.rsvpCount} RSVPs'),
                          _MiniReachPill(label: '${repository.soldForEvent(event.id)} tickets'),
                          _MiniReachPill(label: event.allowSharing ? 'Share link on' : 'Share link off'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.campaign});

  final PromotionCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final statusColor = switch (campaign.status) {
      PromotionStatus.live => palette.coral,
      PromotionStatus.scheduled => palette.teal,
      PromotionStatus.completed => palette.gold,
      PromotionStatus.draft => palette.slate,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(campaign.name, style: context.text.titleLarge?.copyWith(fontSize: 22)),
                      const SizedBox(height: 6),
                      Text(campaign.eventTitle, style: context.text.bodyMedium),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _statusLabel(campaign.status),
                    style: context.text.bodyMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(campaign.message, style: context.text.bodyLarge),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MiniReachPill(label: 'Budget ${formatMoney(campaign.budget)}'),
                _MiniReachPill(label: '${campaign.pushAudience} push'),
                _MiniReachPill(label: '${campaign.smsAudience} SMS'),
                _MiniReachPill(label: formatPromoTime(campaign.scheduledAt)),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: campaign.channels
                  .map(
                    (channel) => Chip(
                      label: Text(_channelLabel(channel)),
                      backgroundColor: palette.canvas,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(PromotionStatus status) => switch (status) {
        PromotionStatus.draft => 'Draft',
        PromotionStatus.scheduled => 'Scheduled',
        PromotionStatus.live => 'Live',
        PromotionStatus.completed => 'Completed',
      };

  String _channelLabel(PromotionChannel channel) => switch (channel) {
        PromotionChannel.push => 'Push',
        PromotionChannel.sms => 'SMS',
        PromotionChannel.shareLink => 'Share Link',
        PromotionChannel.featured => 'Featured',
      };
}

class _MiniReachPill extends StatelessWidget {
  const _MiniReachPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.palette.ink)),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      side: BorderSide.none,
      backgroundColor: Colors.white,
      selectedColor: context.palette.ink,
      labelStyle: context.text.bodyMedium?.copyWith(
        color: selected ? Colors.white : context.palette.ink,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
