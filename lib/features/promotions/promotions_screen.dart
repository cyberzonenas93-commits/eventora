import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/visuals/vennuzo_visuals.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../domain/models/account_models.dart';
import '../../domain/models/promotion_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_heading.dart';
import '../account/auth_prompt_sheet.dart';
import '../creative/creative_services_screen.dart';
import '../manage/host_access_screen.dart';
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
    final repository = context.watch<VennuzoRepository>();
    final session = context.watch<VennuzoSessionController>();
    final canLaunchCampaigns =
        session.viewer.hasOrganizerAccess || session.viewer.hasAdminAccess;
    final needsHostAccess = !session.isGuest && !canLaunchCampaigns;
    final hasPendingHostAccess = session.viewer.hasPendingOrganizerApplication;
    final hasRejectedHostAccess =
        session.viewer.organizerApplicationStatus ==
        OrganizerApplicationStatus.rejected;
    final campaigns = repository.campaigns;
    final filtered = _filter == null
        ? campaigns
        : campaigns.where((campaign) => campaign.status == _filter).toList();
    final liveCount = campaigns
        .where((campaign) => campaign.status == PromotionStatus.live)
        .length;
    final scheduledCount = campaigns
        .where((campaign) => campaign.status == PromotionStatus.scheduled)
        .length;
    final featuredCount = campaigns
        .where(
          (campaign) => campaign.channels.contains(PromotionChannel.featured),
        )
        .length;
    final announcementCount = campaigns
        .where(
          (campaign) =>
              campaign.channels.contains(PromotionChannel.announcement),
        )
        .length;
    final totalReach = campaigns.fold<int>(
      0,
      (sum, campaign) => sum + campaign.pushAudience + campaign.smsAudience,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      children: [
        _PromotionsHero(
          onLaunch: () => session.isGuest
              ? _promptForAccess(context)
              : needsHostAccess
              ? _openHostAccess(context)
              : _launchCampaign(context),
          isGuest: session.isGuest,
          needsHostAccess: needsHostAccess,
          hasPendingHostAccess: hasPendingHostAccess,
          hasRejectedHostAccess: hasRejectedHostAccess,
          campaignCount: campaigns.length,
          totalReach: totalReach,
        ),
        const SizedBox(height: 22),
        if (session.isGuest)
          _GuestReachPitch(onContinue: () => _promptForAccess(context))
        else ...[
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
                label: 'Live now',
                value: '$liveCount',
                icon: Icons.wifi_tethering_outlined,
                highlight: context.palette.coral,
              ),
              MetricTile(
                label: 'People reached',
                value: '$totalReach',
                icon: Icons.groups_2_outlined,
                highlight: context.palette.teal,
              ),
            ],
          ),
          const SizedBox(height: 28),
          _PlacementInventorySection(
            featuredCount: featuredCount,
            announcementCount: announcementCount,
            onLaunch: () => needsHostAccess
                ? _openHostAccess(context)
                : _launchCampaign(context),
          ),
          const SizedBox(height: 28),
          _CreativeServicesPromoCard(
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CreativeServicesScreen(),
              ),
            ),
          ),
          const SizedBox(height: 28),
          SectionHeading(title: 'Channels', subtitle: null),
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
                onTap: () =>
                    setState(() => _filter = PromotionStatus.scheduled),
              ),
              _FilterChip(
                label: 'Completed',
                selected: _filter == PromotionStatus.completed,
                onTap: () =>
                    setState(() => _filter = PromotionStatus.completed),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _EventReachSection(),
          const SizedBox(height: 24),
          SectionHeading(title: 'Campaigns', subtitle: null),
          const SizedBox(height: 14),
          if (needsHostAccess)
            EmptyStateCard(
              title: hasPendingHostAccess
                  ? 'Host access is in review'
                  : hasRejectedHostAccess
                  ? 'Update host access to launch campaigns'
                  : 'Finish host access to launch campaigns',
              icon: Icons.storefront_outlined,
              actionLabel: hasPendingHostAccess
                  ? 'Review status'
                  : hasRejectedHostAccess
                  ? 'Update host access'
                  : 'Open host access',
              onAction: () => _openHostAccess(context),
            )
          else if (repository.managedEvents.isEmpty)
            EmptyStateCard(
              title: 'Create an event before promoting it',
              icon: Icons.event_available_outlined,
            )
          else if (filtered.isEmpty)
            EmptyStateCard(
              title: 'Nothing matches this filter yet',
              body: scheduledCount == 0 ? null : 'Try another filter.',
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
      ],
    );
  }

  Future<void> _launchCampaign(BuildContext context) async {
    final campaign = await showCampaignComposerSheet(context);
    if (campaign != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${campaign.name}" is ready to send.')),
      );
    }
  }

  void _promptForAccess(BuildContext context) {
    showAuthPromptSheet(
      context,
      title: 'Continue to reach more guests',
      body: 'Sign in or create an account to promote events from Vennuzo.',
    );
  }

  void _openHostAccess(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HostAccessScreen()));
  }
}

class _CreativeServicesPromoCard extends StatelessWidget {
  const _CreativeServicesPromoCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: VennuzoTheme.surface,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        border: Border.all(color: VennuzoTheme.borderBright),
        boxShadow: VennuzoTheme.shadowResting,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: VennuzoTheme.brandGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Flyers and table packages',
                  style: context.text.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Generate branded creative for GHS 50 from the same services wallet.',
                  style: context.text.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: onOpen,
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'Open creative services',
          ),
        ],
      ),
    );
  }
}

class _GuestReachPitch extends StatelessWidget {
  const _GuestReachPitch({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: VennuzoTheme.surface,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        border: Border.all(color: VennuzoTheme.borderBright),
        boxShadow: VennuzoTheme.shadowResting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
                  gradient: VennuzoTheme.brandGradient,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Built for organizers',
                  style: context.text.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Turn an event or place into a campaign with featured placement, sponsored spotlight, push audiences, and SMS reminders.',
            style: context.text.bodyLarge,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _MiniReachPill(label: 'Featured slots'),
              _MiniReachPill(label: 'Push + SMS'),
              _MiniReachPill(label: 'Share QR'),
            ],
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: onContinue,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Continue with account'),
          ),
        ],
      ),
    );
  }
}

class _PromotionsHero extends StatelessWidget {
  const _PromotionsHero({
    required this.onLaunch,
    required this.isGuest,
    required this.needsHostAccess,
    required this.hasPendingHostAccess,
    required this.hasRejectedHostAccess,
    required this.campaignCount,
    required this.totalReach,
  });

  final VoidCallback onLaunch;
  final bool isGuest;
  final bool needsHostAccess;
  final bool hasPendingHostAccess;
  final bool hasRejectedHostAccess;
  final int campaignCount;
  final int totalReach;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 620;

        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: palette.coral.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
              ),
              child: Icon(Icons.campaign_outlined, color: palette.coral),
            ),
            const SizedBox(height: 18),
            Text(
              'Reach',
              style: context.text.bodyLarge?.copyWith(
                color: palette.coral,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(_headline, style: context.text.headlineSmall),
            const SizedBox(height: 10),
            Text(_body, style: context.text.bodyLarge),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MiniReachPill(label: '$campaignCount campaigns'),
                _MiniReachPill(label: '$totalReach reached'),
                const _MiniReachPill(label: 'Push + SMS'),
              ],
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: ElevatedButton.icon(
                onPressed: onLaunch,
                icon: Icon(
                  isGuest ? Icons.login_rounded : Icons.rocket_launch_outlined,
                ),
                label: Text(_actionLabel),
              ),
            ),
          ],
        );

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
            color: palette.card,
            border: Border.all(color: palette.border),
            boxShadow: VennuzoTheme.shadowResting,
          ),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: copy),
                    const SizedBox(width: 22),
                    const _ReachHeroVisual(),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    copy,
                    const SizedBox(height: 20),
                    const _ReachHeroVisual(),
                  ],
                ),
        );
      },
    );
  }

  String get _headline {
    if (isGuest) return 'Promote an event in minutes.';
    if (!needsHostAccess) return 'Launch campaigns fast.';
    if (hasPendingHostAccess) return 'Host access is in review.';
    if (hasRejectedHostAccess) return 'Update host access.';
    return 'Finish host access.';
  }

  String get _body {
    if (isGuest) {
      return 'Create a host profile to book featured placements, push audiences, and SMS reminders.';
    }
    if (!needsHostAccess) {
      return 'Plan placements, forecast reach, and send campaigns from one workspace.';
    }
    if (hasPendingHostAccess) {
      return 'Your organizer application is waiting for approval before campaigns can launch.';
    }
    return 'Complete organizer verification to unlock paid reach and campaign tools.';
  }

  String get _actionLabel {
    if (isGuest) return 'Start reach setup';
    if (!needsHostAccess) return 'Launch campaign';
    if (hasPendingHostAccess) return 'Review status';
    if (hasRejectedHostAccess) return 'Update host access';
    return 'Open host access';
  }
}

class _ReachHeroVisual extends StatelessWidget {
  const _ReachHeroVisual();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      width: double.infinity,
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        border: Border.all(
          color: context.palette.border.withValues(alpha: 0.5),
        ),
        image: const DecorationImage(
          image: AssetImage(VennuzoVisuals.campaignReach),
          fit: BoxFit.cover,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              VennuzoTheme.background.withValues(alpha: 0.58),
            ],
          ),
        ),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Campaign reach',
              style: context.text.titleMedium?.copyWith(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlacementInventorySection extends StatelessWidget {
  const _PlacementInventorySection({
    required this.featuredCount,
    required this.announcementCount,
    required this.onLaunch,
  });

  final int featuredCount;
  final int announcementCount;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 680;
        final gap = twoColumns ? 14.0 : 12.0;
        final cardWidth = twoColumns
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(title: 'Premium placements', subtitle: null),
            const SizedBox(height: 14),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                _PlacementCard(
                  width: cardWidth,
                  title: 'Featured banner',
                  stat: '$featuredCount campaigns booked',
                  detail: 'Pin an event into high-visibility discovery space.',
                  icon: Icons.workspace_premium_outlined,
                  onLaunch: onLaunch,
                ),
                _PlacementCard(
                  width: cardWidth,
                  title: 'Fullscreen announcement',
                  stat: '$announcementCount campaigns booked',
                  detail: 'Use a timed takeover for launches and final pushes.',
                  icon: Icons.open_in_full_outlined,
                  onLaunch: onLaunch,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _EventReachSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final events = repository.managedEvents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(title: 'Reach by event', subtitle: null),
        const SizedBox(height: 14),
        if (events.isEmpty)
          const SizedBox.shrink()
        else
          ...events.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _EventReachCard(
                title: event.title,
                pushAudience: repository.pushAudienceFor(event.id),
                smsAudience: repository.smsAudienceFor(event.id),
                rsvps: event.rsvpCount,
                sold: repository.soldForEvent(event.id),
                sharingEnabled: event.allowSharing,
              ),
            ),
          ),
      ],
    );
  }
}

class _EventReachCard extends StatelessWidget {
  const _EventReachCard({
    required this.title,
    required this.pushAudience,
    required this.smsAudience,
    required this.rsvps,
    required this.sold,
    required this.sharingEnabled,
  });

  final String title;
  final int pushAudience;
  final int smsAudience;
  final int rsvps;
  final int sold;
  final bool sharingEnabled;

  @override
  Widget build(BuildContext context) {
    final maxValue = [
      pushAudience,
      smsAudience,
      rsvps,
      sold,
      1,
    ].reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Text(
                    title,
                    style: context.text.titleLarge?.copyWith(fontSize: 20),
                  ),
                ),
                _MiniReachPill(
                  label: sharingEnabled ? 'Sharing on' : 'Sharing off',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ReachMeterRow(
              label: 'Push',
              value: pushAudience,
              maxValue: maxValue,
              color: context.palette.coral,
            ),
            const SizedBox(height: 10),
            _ReachMeterRow(
              label: 'SMS',
              value: smsAudience,
              maxValue: maxValue,
              color: context.palette.primaryStart,
            ),
            const SizedBox(height: 10),
            _ReachMeterRow(
              label: 'RSVPs',
              value: rsvps,
              maxValue: maxValue,
              color: context.palette.teal,
            ),
            const SizedBox(height: 10),
            _ReachMeterRow(
              label: 'Tickets',
              value: sold,
              maxValue: maxValue,
              color: context.palette.gold,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReachMeterRow extends StatelessWidget {
  const _ReachMeterRow({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  final String label;
  final int value;
  final int maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue == 0 ? 0.0 : value / maxValue;

    return Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: context.text.bodyMedium?.copyWith(
              color: context.palette.slate,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.04, 1),
              minHeight: 8,
              backgroundColor: context.palette.canvas,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 56,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: context.text.bodyMedium?.copyWith(
              color: context.palette.ink,
              fontWeight: FontWeight.w700,
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
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        campaign.name,
                        style: context.text.titleLarge?.copyWith(fontSize: 22),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        campaign.targetLabel,
                        style: context.text.bodyMedium,
                      ),
                    ],
                  ),
                ),
                _CampaignStatusPill(
                  label: _statusLabel(campaign.status),
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              campaign.message,
              style: context.text.bodyLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
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
    PromotionChannel.featured => 'Featured Banner',
    PromotionChannel.announcement => 'Fullscreen Announcement',
  };
}

class _PlacementCard extends StatelessWidget {
  const _PlacementCard({
    required this.width,
    required this.title,
    required this.stat,
    required this.detail,
    required this.icon,
    required this.onLaunch,
  });

  final double width;
  final String title;
  final String stat;
  final String detail;
  final IconData icon;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.coral.withValues(alpha: 0.18),
                      palette.gold.withValues(alpha: 0.14),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: palette.coral),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: context.text.titleLarge?.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 6),
              Text(detail, style: context.text.bodyMedium),
              const SizedBox(height: 14),
              _MiniReachPill(label: stat),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onLaunch,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('Use placement'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CampaignStatusPill extends StatelessWidget {
  const _CampaignStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
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
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(color: context.palette.ink),
      ),
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
      side: BorderSide(color: VennuzoTheme.borderBright),
      backgroundColor: VennuzoTheme.surfaceElevated,
      selectedColor: VennuzoTheme.primaryStart,
      labelStyle: context.text.bodyMedium?.copyWith(
        color: selected ? const Color(0xFF031018) : VennuzoTheme.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
