enum PromotionStatus { draft, scheduled, live, completed }

enum PromotionChannel { push, sms, shareLink, featured, announcement }

enum PromotionTargetType { event, place }

enum CampaignObjective {
  sellTickets,
  driveRsvps,
  fillTables,
  boostAwareness,
  retargetInterest,
  lastCall,
}

enum AudienceStrategy {
  recommended,
  highIntent,
  ownedCrm,
  broadDiscovery,
  retargeting,
}

enum OptimizationGoal { conversions, reach, clicks, rsvps, tables }

enum BidStrategy { lowestCost, balanced, premiumAttention }

enum CreativeMode { single, abTest }

class PromotionCampaign {
  const PromotionCampaign({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    this.targetType = PromotionTargetType.event,
    String? targetId,
    String? targetTitle,
    required this.name,
    this.createdByUserId,
    required this.status,
    required this.channels,
    required this.scheduledAt,
    required this.pushAudience,
    required this.smsAudience,
    required this.shareLinkEnabled,
    this.audienceSources = const <String>['event_rsvps', 'ticket_buyers'],
    required this.budget,
    required this.message,
    required this.createdAt,
    this.objective = CampaignObjective.sellTickets,
    this.audienceStrategy = AudienceStrategy.recommended,
    this.optimizationGoal = OptimizationGoal.conversions,
    this.bidStrategy = BidStrategy.balanced,
    this.creativeMode = CreativeMode.single,
    this.frequencyCap = 2,
    this.budgetCapGhs,
  }) : _targetId = targetId,
       _targetTitle = targetTitle;

  final String id;
  final String eventId;
  final String eventTitle;
  final PromotionTargetType targetType;
  final String? _targetId;
  final String? _targetTitle;
  final String name;
  final String? createdByUserId;
  final PromotionStatus status;
  final List<PromotionChannel> channels;
  final DateTime? scheduledAt;
  final int pushAudience;
  final int smsAudience;
  final bool shareLinkEnabled;
  final List<String> audienceSources;
  final double budget;
  final String message;
  final DateTime createdAt;
  final CampaignObjective objective;
  final AudienceStrategy audienceStrategy;
  final OptimizationGoal optimizationGoal;
  final BidStrategy bidStrategy;
  final CreativeMode creativeMode;
  final int frequencyCap;
  final double? budgetCapGhs;

  String get targetId {
    final value = _targetId?.trim() ?? '';
    return value.isEmpty ? eventId : value;
  }

  String get targetTitle {
    final value = _targetTitle?.trim() ?? '';
    return value.isEmpty ? eventTitle : value;
  }

  String get targetLabel => targetType == PromotionTargetType.place
      ? 'Place: $targetTitle'
      : 'Event: $targetTitle';

  PromotionCampaign copyWith({
    PromotionTargetType? targetType,
    String? targetId,
    String? targetTitle,
    String? createdByUserId,
    bool clearCreatedByUserId = false,
    PromotionStatus? status,
    DateTime? scheduledAt,
    List<PromotionChannel>? channels,
    int? pushAudience,
    int? smsAudience,
    bool? shareLinkEnabled,
    List<String>? audienceSources,
    double? budget,
    String? message,
    CampaignObjective? objective,
    AudienceStrategy? audienceStrategy,
    OptimizationGoal? optimizationGoal,
    BidStrategy? bidStrategy,
    CreativeMode? creativeMode,
    int? frequencyCap,
    double? budgetCapGhs,
    bool clearBudgetCapGhs = false,
  }) {
    return PromotionCampaign(
      id: id,
      eventId: eventId,
      eventTitle: eventTitle,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? _targetId,
      targetTitle: targetTitle ?? _targetTitle,
      name: name,
      createdByUserId: clearCreatedByUserId
          ? null
          : createdByUserId ?? this.createdByUserId,
      status: status ?? this.status,
      channels: channels ?? this.channels,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      pushAudience: pushAudience ?? this.pushAudience,
      smsAudience: smsAudience ?? this.smsAudience,
      shareLinkEnabled: shareLinkEnabled ?? this.shareLinkEnabled,
      audienceSources: audienceSources ?? this.audienceSources,
      budget: budget ?? this.budget,
      message: message ?? this.message,
      createdAt: createdAt,
      objective: objective ?? this.objective,
      audienceStrategy: audienceStrategy ?? this.audienceStrategy,
      optimizationGoal: optimizationGoal ?? this.optimizationGoal,
      bidStrategy: bidStrategy ?? this.bidStrategy,
      creativeMode: creativeMode ?? this.creativeMode,
      frequencyCap: frequencyCap ?? this.frequencyCap,
      budgetCapGhs: clearBudgetCapGhs
          ? null
          : budgetCapGhs ?? this.budgetCapGhs,
    );
  }
}

class RsvpRecord {
  const RsvpRecord({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    this.attendeeUserId,
    required this.name,
    required this.phone,
    required this.guestCount,
    required this.bookTable,
    required this.createdAt,
  });

  final String id;
  final String eventId;
  final String eventTitle;
  final String? attendeeUserId;
  final String name;
  final String phone;
  final int guestCount;
  final bool bookTable;
  final DateTime createdAt;
}

extension CampaignObjectiveBackendName on CampaignObjective {
  String get backendName => switch (this) {
    CampaignObjective.sellTickets => 'sell_tickets',
    CampaignObjective.driveRsvps => 'drive_rsvps',
    CampaignObjective.fillTables => 'fill_tables',
    CampaignObjective.boostAwareness => 'boost_awareness',
    CampaignObjective.retargetInterest => 'retarget_interest',
    CampaignObjective.lastCall => 'last_call',
  };
}

extension AudienceStrategyBackendName on AudienceStrategy {
  String get backendName => switch (this) {
    AudienceStrategy.recommended => 'recommended',
    AudienceStrategy.highIntent => 'high_intent',
    AudienceStrategy.ownedCrm => 'owned_crm',
    AudienceStrategy.broadDiscovery => 'broad_discovery',
    AudienceStrategy.retargeting => 'retargeting',
  };
}

extension OptimizationGoalBackendName on OptimizationGoal {
  String get backendName => switch (this) {
    OptimizationGoal.conversions => 'conversions',
    OptimizationGoal.reach => 'reach',
    OptimizationGoal.clicks => 'clicks',
    OptimizationGoal.rsvps => 'rsvps',
    OptimizationGoal.tables => 'tables',
  };
}

extension BidStrategyBackendName on BidStrategy {
  String get backendName => switch (this) {
    BidStrategy.lowestCost => 'lowest_cost',
    BidStrategy.balanced => 'balanced',
    BidStrategy.premiumAttention => 'premium_attention',
  };
}

extension CreativeModeBackendName on CreativeMode {
  String get backendName => switch (this) {
    CreativeMode.single => 'single',
    CreativeMode.abTest => 'ab_test',
  };
}
