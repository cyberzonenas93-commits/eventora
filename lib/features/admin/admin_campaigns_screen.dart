import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/eventora_repository.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/promotion_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_heading.dart';
import '../promotions/campaign_composer_sheet.dart';

class AdminCampaignsScreen extends StatelessWidget {
  const AdminCampaignsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<EventoraRepository>();
    final campaigns = repository.adminVisibleCampaigns;
    final events = repository.adminVisibleEvents;
    final totalReach = campaigns.fold<int>(
      0,
      (sum, campaign) => sum + campaign.pushAudience + campaign.smsAudience,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        const _CampaignsHero(),
        const SizedBox(height: 22),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            MetricTile(
              label: 'Campaigns',
              value: '${campaigns.length}',
              icon: Icons.campaign_outlined,
            ),
            MetricTile(
              label: 'Live',
              value: '${repository.liveCampaignCount}',
              icon: Icons.wifi_tethering_outlined,
              highlight: context.palette.coral,
            ),
            MetricTile(
              label: 'Scheduled',
              value: '${repository.scheduledCampaignCount}',
              icon: Icons.schedule_outlined,
              highlight: context.palette.gold,
            ),
            MetricTile(
              label: 'Audience reach',
              value: '$totalReach',
              icon: Icons.groups_2_outlined,
              highlight: context.palette.teal,
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'SMS and push routing',
          subtitle:
              'Plan broadcast messaging around approved events, with clean controls for push, SMS, and premium placement.',
        ),
        const SizedBox(height: 14),
        ...events.map(
          (event) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _EventAudienceCard(event: event),
          ),
        ),
        const SizedBox(height: 24),
        SectionHeading(
          title: 'Campaign history',
          subtitle:
              'Every push, SMS, share-link, or featured placement stays tied to an event for auditing and reporting.',
          actionLabel: 'Launch',
          onAction: () => _launchCampaign(context),
        ),
        const SizedBox(height: 14),
        if (campaigns.isEmpty)
          EmptyStateCard(
            title: 'No campaigns yet',
            body:
                'Once an event needs promotion, launch the first campaign here and fan out across push, SMS, share links, and featured placement.',
            icon: Icons.outbound_outlined,
            actionLabel: 'Launch campaign',
            onAction: () => _launchCampaign(context),
          )
        else
          ...campaigns.map(
            (campaign) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
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
        SnackBar(content: Text('Campaign "${campaign.name}" launched.')),
      );
    }
  }
}

class _CampaignsHero extends StatelessWidget {
  const _CampaignsHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [context.palette.teal, context.palette.ink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Campaign control',
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Coordinate push, SMS, share links, and featured placement from the admin console.',
            style: context.text.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            'This is where event campaigns are scheduled, reviewed, and sent with clear audience intent.',
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventAudienceCard extends StatelessWidget {
  const _EventAudienceCard({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<EventoraRepository>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.title,
              style: context.text.titleLarge?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 6),
            Text(
              '${repository.pushAudienceFor(event.id)} push audience • ${repository.smsAudienceFor(event.id)} SMS audience',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _CampaignPill(label: '${event.rsvpCount} RSVPs'),
                _CampaignPill(
                  label: '${repository.soldForEvent(event.id)} tickets',
                ),
                _CampaignPill(
                  label: event.allowSharing ? 'Share ready' : 'Sharing off',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.campaign});

  final PromotionCampaign campaign;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        campaign.name,
                        style: context.text.titleLarge?.copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: 6),
                      Text(campaign.eventTitle, style: context.text.bodyMedium),
                    ],
                  ),
                ),
                _CampaignPill(
                  label: campaign.status.name.toUpperCase(),
                  color: switch (campaign.status) {
                    PromotionStatus.live => context.palette.coral,
                    PromotionStatus.scheduled => context.palette.gold,
                    PromotionStatus.completed => context.palette.teal,
                    PromotionStatus.draft => context.palette.ink,
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(campaign.message, style: context.text.bodyMedium),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _CampaignPill(label: 'Budget ${formatMoney(campaign.budget)}'),
                _CampaignPill(label: '${campaign.pushAudience} push'),
                _CampaignPill(label: '${campaign.smsAudience} SMS'),
                _CampaignPill(label: formatPromoTime(campaign.scheduledAt)),
                ...campaign.channels.map(
                  (channel) => _CampaignPill(label: _channelLabel(channel)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _channelLabel(PromotionChannel channel) {
    return switch (channel) {
      PromotionChannel.push => 'Push',
      PromotionChannel.sms => 'SMS',
      PromotionChannel.shareLink => 'Share link',
      PromotionChannel.featured => 'Featured banner',
      PromotionChannel.announcement => 'Fullscreen announcement',
    };
  }
}

class _CampaignPill extends StatelessWidget {
  const _CampaignPill({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.palette.canvas;
    final foreground = color == null ? context.palette.ink : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
