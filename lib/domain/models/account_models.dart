enum EventoraWorkspaceFace { attendee, admin }

enum OrganizerApplicationStatus {
  notStarted,
  draft,
  submitted,
  underReview,
  approved,
  rejected,
}

class EventoraNotificationPrefs {
  const EventoraNotificationPrefs({
    this.pushEnabled = true,
    this.smsEnabled = true,
    this.marketingOptIn = false,
  });

  final bool pushEnabled;
  final bool smsEnabled;
  final bool marketingOptIn;

  EventoraNotificationPrefs copyWith({
    bool? pushEnabled,
    bool? smsEnabled,
    bool? marketingOptIn,
  }) {
    return EventoraNotificationPrefs(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      smsEnabled: smsEnabled ?? this.smsEnabled,
      marketingOptIn: marketingOptIn ?? this.marketingOptIn,
    );
  }
}

class EventoraViewer {
  const EventoraViewer({
    required this.displayName,
    required this.isAuthenticated,
    this.notificationPrefs = const EventoraNotificationPrefs(),
    this.roles = const <String>[],
    this.activeFace = EventoraWorkspaceFace.attendee,
    this.uid,
    this.email,
    this.phone,
    this.adminRole,
    this.defaultOrganizationId,
    this.organizerApplicationStatus = OrganizerApplicationStatus.notStarted,
    this.organizerReviewNotes,
    this.hasCustomerProfile = false,
    this.hasAdminProfile = false,
  });

  const EventoraViewer.guest()
    : displayName = 'Guest',
      isAuthenticated = false,
      notificationPrefs = const EventoraNotificationPrefs(),
      roles = const <String>[],
      activeFace = EventoraWorkspaceFace.attendee,
      uid = null,
      email = null,
      phone = null,
      adminRole = null,
      defaultOrganizationId = null,
      organizerApplicationStatus = OrganizerApplicationStatus.notStarted,
      organizerReviewNotes = null,
      hasCustomerProfile = false,
      hasAdminProfile = false;

  final String? uid;
  final String displayName;
  final String? email;
  final String? phone;
  final bool isAuthenticated;
  final EventoraNotificationPrefs notificationPrefs;
  final List<String> roles;
  final EventoraWorkspaceFace activeFace;
  final String? adminRole;
  final String? defaultOrganizationId;
  final OrganizerApplicationStatus organizerApplicationStatus;
  final String? organizerReviewNotes;
  final bool hasCustomerProfile;
  final bool hasAdminProfile;

  bool get isGuest => !isAuthenticated;
  bool get isAdminWorkspace => activeFace == EventoraWorkspaceFace.admin;
  bool get hasOrganizerAccess =>
      _hasRole('organizer') ||
      organizerApplicationStatus == OrganizerApplicationStatus.approved;
  bool get hasAdminAccess =>
      hasAdminProfile || _hasRole('admin') || _hasRole('superadmin');
  bool get hasSuperAdminAccess =>
      (adminRole ?? '').toLowerCase() == 'superadmin' || _hasRole('superadmin');
  bool get hasPendingOrganizerApplication =>
      organizerApplicationStatus == OrganizerApplicationStatus.submitted ||
      organizerApplicationStatus == OrganizerApplicationStatus.underReview;
  bool get canStartOrganizerApplication =>
      !hasOrganizerAccess &&
      (organizerApplicationStatus == OrganizerApplicationStatus.notStarted ||
          organizerApplicationStatus == OrganizerApplicationStatus.draft ||
          organizerApplicationStatus == OrganizerApplicationStatus.rejected);
  String get organizerStatusLabel => switch (organizerApplicationStatus) {
        OrganizerApplicationStatus.notStarted => 'Not started',
        OrganizerApplicationStatus.draft => 'Draft in progress',
        OrganizerApplicationStatus.submitted => 'Submitted',
        OrganizerApplicationStatus.underReview => 'Under review',
        OrganizerApplicationStatus.approved => 'Approved',
        OrganizerApplicationStatus.rejected => 'Needs changes',
      };
  bool get canUseAttendeeWorkspace =>
      isGuest || hasCustomerProfile || hasOrganizerAccess || !hasAdminAccess;
  bool get canChooseWorkspace => hasAdminAccess && canUseAttendeeWorkspace;

  String get badgeLabel {
    if (isGuest) {
      return 'Guest access';
    }
    if (isAdminWorkspace) {
      return hasSuperAdminAccess ? 'Superadmin console' : 'Admin console';
    }
    if (hasOrganizerAccess) {
      return 'Organizer workspace';
    }
    return 'Attendee workspace';
  }

  String get faceTitle {
    if (isGuest) {
      return 'Eventora';
    }
    return isAdminWorkspace
        ? (hasSuperAdminAccess ? 'Superadmin Console' : 'Admin Console')
        : 'Eventora';
  }

  EventoraViewer copyWith({
    String? uid,
    String? displayName,
    String? email,
    String? phone,
    bool? isAuthenticated,
    EventoraNotificationPrefs? notificationPrefs,
    List<String>? roles,
    EventoraWorkspaceFace? activeFace,
    String? adminRole,
    bool clearAdminRole = false,
    String? defaultOrganizationId,
    bool clearDefaultOrganizationId = false,
    OrganizerApplicationStatus? organizerApplicationStatus,
    String? organizerReviewNotes,
    bool clearOrganizerReviewNotes = false,
    bool? hasCustomerProfile,
    bool? hasAdminProfile,
  }) {
    return EventoraViewer(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      notificationPrefs: notificationPrefs ?? this.notificationPrefs,
      roles: roles ?? this.roles,
      activeFace: activeFace ?? this.activeFace,
      adminRole: clearAdminRole ? null : adminRole ?? this.adminRole,
      defaultOrganizationId: clearDefaultOrganizationId
          ? null
          : defaultOrganizationId ?? this.defaultOrganizationId,
      organizerApplicationStatus:
          organizerApplicationStatus ?? this.organizerApplicationStatus,
      organizerReviewNotes: clearOrganizerReviewNotes
          ? null
          : organizerReviewNotes ?? this.organizerReviewNotes,
      hasCustomerProfile: hasCustomerProfile ?? this.hasCustomerProfile,
      hasAdminProfile: hasAdminProfile ?? this.hasAdminProfile,
    );
  }

  bool _hasRole(String value) {
    final normalized = value.trim().toLowerCase();
    return roles.any((role) => role.trim().toLowerCase() == normalized);
  }
}
