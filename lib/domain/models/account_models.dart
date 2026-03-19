enum VennuzoWorkspaceFace { attendee, admin }

enum OrganizerApplicationStatus {
  notStarted,
  draft,
  active,
  submitted,
  underReview,
  approved,
  rejected,
}

class VennuzoNotificationPrefs {
  const VennuzoNotificationPrefs({
    this.pushEnabled = true,
    this.smsEnabled = true,
    this.marketingOptIn = false,
  });

  final bool pushEnabled;
  final bool smsEnabled;
  final bool marketingOptIn;

  VennuzoNotificationPrefs copyWith({
    bool? pushEnabled,
    bool? smsEnabled,
    bool? marketingOptIn,
  }) {
    return VennuzoNotificationPrefs(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      smsEnabled: smsEnabled ?? this.smsEnabled,
      marketingOptIn: marketingOptIn ?? this.marketingOptIn,
    );
  }
}

class VennuzoViewer {
  const VennuzoViewer({
    required this.displayName,
    required this.isAuthenticated,
    this.notificationPrefs = const VennuzoNotificationPrefs(),
    this.roles = const <String>[],
    this.activeFace = VennuzoWorkspaceFace.attendee,
    this.uid,
    this.email,
    this.phone,
    this.dateOfBirth,
    this.photoUrl,
    this.adminRole,
    this.defaultOrganizationId,
    this.organizerApplicationStatus = OrganizerApplicationStatus.notStarted,
    this.organizerReviewNotes,
    this.hasCustomerProfile = false,
    this.hasAdminProfile = false,
  });

  const VennuzoViewer.guest()
    : displayName = 'Guest',
      isAuthenticated = false,
      notificationPrefs = const VennuzoNotificationPrefs(),
      roles = const <String>[],
      activeFace = VennuzoWorkspaceFace.attendee,
      uid = null,
      email = null,
      phone = null,
      dateOfBirth = null,
      photoUrl = null,
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
  final DateTime? dateOfBirth;
  final String? photoUrl;
  final bool isAuthenticated;
  final VennuzoNotificationPrefs notificationPrefs;
  final List<String> roles;
  final VennuzoWorkspaceFace activeFace;
  final String? adminRole;
  final String? defaultOrganizationId;
  final OrganizerApplicationStatus organizerApplicationStatus;
  final String? organizerReviewNotes;
  final bool hasCustomerProfile;
  final bool hasAdminProfile;

  bool get isGuest => !isAuthenticated;
  bool get isAdminWorkspace => activeFace == VennuzoWorkspaceFace.admin;
  bool get hasOrganizerAccess =>
      _hasRole('organizer') ||
      organizerApplicationStatus == OrganizerApplicationStatus.active ||
      organizerApplicationStatus == OrganizerApplicationStatus.approved;
  bool get hasAdminAccess =>
      hasAdminProfile || _hasRole('admin') || _hasRole('superadmin');
  bool get hasSuperAdminAccess =>
      (adminRole ?? '').toLowerCase() == 'superadmin' || _hasRole('superadmin');
  bool get hasMainAppAccess =>
      isGuest ||
      _hasRole('attendee') ||
      hasOrganizerAccess ||
      (hasCustomerProfile && !hasAdminAccess);
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
    OrganizerApplicationStatus.active => 'Live',
    OrganizerApplicationStatus.submitted => 'Submitted',
    OrganizerApplicationStatus.underReview => 'Under review',
    OrganizerApplicationStatus.approved => 'Approved',
    OrganizerApplicationStatus.rejected => 'Needs changes',
  };
  bool get canUseAttendeeWorkspace => hasMainAppAccess;
  bool get canChooseWorkspace => hasAdminAccess && hasMainAppAccess;

  String get badgeLabel {
    if (isGuest) {
      return 'Guest access';
    }
    if (isAdminWorkspace) {
      return hasSuperAdminAccess ? 'Superadmin console' : 'Admin console';
    }
    if (hasOrganizerAccess) {
      return 'Organizer app';
    }
    return 'Vennuzo app';
  }

  String get faceTitle {
    if (isGuest) {
      return 'Vennuzo';
    }
    return isAdminWorkspace
        ? (hasSuperAdminAccess ? 'Superadmin Console' : 'Admin Console')
        : 'Vennuzo';
  }

  VennuzoViewer copyWith({
    String? uid,
    String? displayName,
    String? email,
    String? phone,
    DateTime? dateOfBirth,
    String? photoUrl,
    bool? isAuthenticated,
    VennuzoNotificationPrefs? notificationPrefs,
    List<String>? roles,
    VennuzoWorkspaceFace? activeFace,
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
    return VennuzoViewer(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      photoUrl: photoUrl ?? this.photoUrl,
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
