import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/services/eventora_notification_service.dart';
import '../domain/models/account_models.dart';

class EventoraAuthFailure implements Exception {
  const EventoraAuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class EventoraSessionController extends ChangeNotifier {
  EventoraSessionController({required bool firebaseEnabled})
    : _firebaseEnabled = firebaseEnabled {
    if (_firebaseEnabled) {
      _isInitializing = true;
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
        _onAuthChanged,
      );
    }
  }

  final bool _firebaseEnabled;
  StreamSubscription<User?>? _authSubscription;

  EventoraViewer _viewer = const EventoraViewer.guest();
  bool _isInitializing = false;
  bool _isProcessing = false;
  EventoraWorkspaceFace? _selectedFace;

  EventoraViewer get viewer => _viewer;
  bool get isGuest => _viewer.isGuest;
  bool get isAuthenticated => _viewer.isAuthenticated;
  bool get isInitializing => _isInitializing;
  bool get isProcessing => _isProcessing;
  bool get firebaseEnabled => _firebaseEnabled;
  bool get isAdminWorkspace => _viewer.isAdminWorkspace;
  bool get hasAdminAccess => _viewer.hasAdminAccess;
  bool get hasSuperAdminAccess => _viewer.hasSuperAdminAccess;
  bool get canChooseWorkspace => _viewer.canChooseWorkspace;
  bool get needsWorkspaceChoice =>
      !_isInitializing && canChooseWorkspace && _selectedFace == null;

  Future<void> _onAuthChanged(User? user) async {
    _isInitializing = true;
    notifyListeners();

    if (user == null) {
      _selectedFace = null;
      _viewer = const EventoraViewer.guest();
      await EventoraNotificationService.instance.bindViewer(_viewer);
      _isInitializing = false;
      notifyListeners();
      return;
    }

    final results = await Future.wait([
      FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      FirebaseFirestore.instance.collection('admins').doc(user.uid).get(),
      FirebaseFirestore.instance
          .collection('organizer_applications')
          .doc(user.uid)
          .get(),
    ]);
    final userProfile = results[0];
    final adminProfile = results[1];
    final organizerApplication = results[2];
    final userData = userProfile.data() ?? <String, dynamic>{};
    final adminData = adminProfile.data() ?? <String, dynamic>{};
    final organizerData = organizerApplication.data() ?? <String, dynamic>{};
    final organizerStatus = _organizerStatusFromData(
      userData: userData,
      organizerData: organizerData,
    );
    final notificationPrefs = _notificationPrefsFromData(
      userData.isNotEmpty ? userData : adminData,
    );
    final roles = _rolesFromData(
      userData: userData,
      adminData: adminData,
      organizerStatus: organizerStatus,
      hasUserProfile: userProfile.exists,
      hasAdminProfile: adminProfile.exists,
    );
    final hasCustomerProfile =
        userProfile.exists || (!adminProfile.exists && user.email != null);
    final hasAdminProfile =
        adminProfile.exists ||
        _containsRole(roles, 'admin') ||
        _containsRole(roles, 'superadmin');
    final activeFace = _resolveActiveFace(
      hasCustomerProfile: hasCustomerProfile,
      hasAdminProfile: hasAdminProfile,
    );
    _viewer = EventoraViewer(
      uid: user.uid,
      displayName: _resolveDisplayName(
        userData: userData,
        adminData: adminData,
        authUser: user,
      ),
      email:
          (userData['email'] as String?) ??
          (adminData['email'] as String?) ??
          user.email,
      phone: _normalizePhone(
        (userData['phone'] as String?) ?? (adminData['phone'] as String?),
      ),
      isAuthenticated: true,
      notificationPrefs: notificationPrefs,
      roles: roles,
      activeFace: activeFace,
      adminRole: _adminRoleFromData(adminData, roles),
      defaultOrganizationId:
          (userData['defaultOrganizationId'] as String?) ??
          (adminData['defaultOrganizationId'] as String?) ??
          (organizerData['organizationId'] as String?),
      organizerApplicationStatus: organizerStatus,
      organizerReviewNotes:
          (organizerData['reviewNotes'] as String?)?.trim().isEmpty == true
          ? null
          : (organizerData['reviewNotes'] as String?),
      hasCustomerProfile: hasCustomerProfile,
      hasAdminProfile: hasAdminProfile,
    );
    await EventoraNotificationService.instance.bindViewer(_viewer);
    _isInitializing = false;
    notifyListeners();
  }

  Future<void> createAccount({
    required String displayName,
    required String email,
    required String password,
    String? phone,
  }) async {
    _ensureFirebaseEnabled();
    await _runGuarded(() async {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
      final user = credential.user;
      if (user == null) {
        throw const EventoraAuthFailure(
          'We could not finish creating the account.',
        );
      }
      await user.updateDisplayName(displayName.trim());
      await _upsertProfile(user, displayName: displayName.trim(), phone: phone);
    });
  }

  Future<void> signIn({required String email, required String password}) async {
    _ensureFirebaseEnabled();
    await _runGuarded(() async {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    });
  }

  Future<void> sendPasswordReset(String email) async {
    _ensureFirebaseEnabled();
    await _runGuarded(() async {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
    });
  }

  Future<void> signOut() async {
    if (!_firebaseEnabled) {
      _selectedFace = null;
      _viewer = const EventoraViewer.guest();
      notifyListeners();
      return;
    }

    await _runGuarded(() async {
      await FirebaseAuth.instance.signOut();
      await EventoraNotificationService.instance.clearBoundToken();
    });
  }

  Future<void> deleteAccount({required String currentPassword}) async {
    _ensureFirebaseEnabled();
    await _runGuarded(() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }
      final email = user.email;
      if (email == null || email.trim().isEmpty) {
        throw const EventoraAuthFailure(
          'This account cannot be deleted from the app until it has a valid email.',
        );
      }

      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );

      final batch = FirebaseFirestore.instance.batch();
      batch.delete(
        FirebaseFirestore.instance.collection('users').doc(user.uid),
      );
      batch.delete(
        FirebaseFirestore.instance.collection('admins').doc(user.uid),
      );
      await batch.commit();
      await EventoraNotificationService.instance.clearBoundToken();
      await user.delete();
    });
  }

  Future<void> updateNotificationPrefs({
    bool? pushEnabled,
    bool? smsEnabled,
    bool? marketingOptIn,
  }) async {
    _ensureFirebaseEnabled();
    final uid = _viewer.uid;
    if (uid == null) {
      throw const EventoraAuthFailure(
        'Sign in before updating notification preferences.',
      );
    }

    final updatedPrefs = _viewer.notificationPrefs.copyWith(
      pushEnabled: pushEnabled,
      smsEnabled: smsEnabled,
      marketingOptIn: marketingOptIn,
    );

    await _runGuarded(() async {
      final batch = FirebaseFirestore.instance.batch();
      final payload = <String, Object?>{
        'notificationPrefs': <String, Object?>{
          'pushEnabled': updatedPrefs.pushEnabled,
          'smsEnabled': updatedPrefs.smsEnabled,
          'marketingOptIn': updatedPrefs.marketingOptIn,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_viewer.hasCustomerProfile || !_viewer.hasAdminProfile) {
        batch.set(
          FirebaseFirestore.instance.collection('users').doc(uid),
          payload,
          SetOptions(merge: true),
        );
      }
      if (_viewer.hasAdminProfile) {
        batch.set(
          FirebaseFirestore.instance.collection('admins').doc(uid),
          payload,
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    });

    _viewer = _viewer.copyWith(notificationPrefs: updatedPrefs);
    notifyListeners();
    await EventoraNotificationService.instance.bindViewer(_viewer);
  }

  void enterAttendeeWorkspace() {
    if (!_viewer.canUseAttendeeWorkspace) {
      return;
    }
    _selectedFace = EventoraWorkspaceFace.attendee;
    _viewer = _viewer.copyWith(activeFace: EventoraWorkspaceFace.attendee);
    notifyListeners();
  }

  void enterAdminWorkspace() {
    if (!_viewer.hasAdminAccess) {
      return;
    }
    _selectedFace = EventoraWorkspaceFace.admin;
    _viewer = _viewer.copyWith(activeFace: EventoraWorkspaceFace.admin);
    notifyListeners();
  }

  void openWorkspaceChooser() {
    if (!_viewer.canChooseWorkspace) {
      return;
    }
    _selectedFace = null;
    notifyListeners();
  }

  Future<void> _upsertProfile(
    User user, {
    required String displayName,
    String? phone,
  }) async {
    final trimmedPhone = phone?.trim();
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      <String, Object?>{
        'displayName': displayName,
        'email': user.email,
        'phone': trimmedPhone == null || trimmedPhone.isEmpty
            ? null
            : trimmedPhone,
        'roles': FieldValue.arrayUnion(const ['attendee']),
        'organizerApplicationStatus': 'notStarted',
        'notificationPrefs': const <String, Object?>{
          'pushEnabled': true,
          'smsEnabled': true,
          'marketingOptIn': false,
        },
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _runGuarded(Future<void> Function() action) async {
    _isProcessing = true;
    notifyListeners();
    try {
      await action();
    } on FirebaseAuthException catch (error) {
      throw EventoraAuthFailure(_friendlyAuthMessage(error));
    } on FirebaseException catch (error) {
      throw EventoraAuthFailure(
        error.message ?? 'Something went wrong. Please try again.',
      );
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  void _ensureFirebaseEnabled() {
    if (_firebaseEnabled) {
      return;
    }
    throw const EventoraAuthFailure(
      'Firebase auth is available on the Android and iOS builds of Eventora.',
    );
  }

  EventoraWorkspaceFace _resolveActiveFace({
    required bool hasCustomerProfile,
    required bool hasAdminProfile,
  }) {
    if (_selectedFace == EventoraWorkspaceFace.admin && hasAdminProfile) {
      return EventoraWorkspaceFace.admin;
    }
    if (_selectedFace == EventoraWorkspaceFace.attendee && hasCustomerProfile) {
      return EventoraWorkspaceFace.attendee;
    }
    if (hasAdminProfile && !hasCustomerProfile) {
      return EventoraWorkspaceFace.admin;
    }
    return EventoraWorkspaceFace.attendee;
  }

  String _resolveDisplayName({
    required Map<String, dynamic> userData,
    required Map<String, dynamic> adminData,
    required User authUser,
  }) {
    final userName = (userData['displayName'] as String?)?.trim();
    if (userName != null && userName.isNotEmpty) {
      return userName;
    }
    final adminName = (adminData['displayName'] as String?)?.trim();
    if (adminName != null && adminName.isNotEmpty) {
      return adminName;
    }
    if (authUser.displayName?.trim().isNotEmpty == true) {
      return authUser.displayName!.trim();
    }
    return _displayNameFromEmail(authUser.email);
  }

  List<String> _rolesFromData({
    required Map<String, dynamic> userData,
    required Map<String, dynamic> adminData,
    required OrganizerApplicationStatus organizerStatus,
    required bool hasUserProfile,
    required bool hasAdminProfile,
  }) {
    final roles = <String>{};
    final userRoles = userData['roles'];
    if (userRoles is Iterable) {
      for (final role in userRoles) {
        final normalized = role.toString().trim().toLowerCase();
        if (normalized.isNotEmpty) {
          roles.add(normalized);
        }
      }
    }
    if (hasUserProfile && roles.isEmpty) {
      roles.add('attendee');
    }
    if (organizerStatus == OrganizerApplicationStatus.approved) {
      roles.add('organizer');
    }
    if (hasAdminProfile) {
      roles.add('admin');
      final adminRole = (adminData['role'] as String?)?.trim().toLowerCase();
      if (adminRole != null && adminRole.isNotEmpty) {
        roles.add(adminRole);
      }
    }
    if (roles.isEmpty) {
      roles.add('attendee');
    }
    return roles.toList()..sort();
  }

  String? _adminRoleFromData(
    Map<String, dynamic> adminData,
    List<String> roles,
  ) {
    final raw = (adminData['role'] as String?)?.trim();
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    if (_containsRole(roles, 'superadmin')) {
      return 'superadmin';
    }
    if (_containsRole(roles, 'admin')) {
      return 'admin';
    }
    return null;
  }

  String _displayNameFromEmail(String? email) {
    if (email == null || email.trim().isEmpty) {
      return 'Eventora user';
    }
    final local = email.split('@').first.trim();
    if (local.isEmpty) {
      return 'Eventora user';
    }
    return local
        .split(RegExp(r'[._-]+'))
        .where((segment) => segment.isNotEmpty)
        .map((segment) => '${segment[0].toUpperCase()}${segment.substring(1)}')
        .join(' ');
  }

  OrganizerApplicationStatus _organizerStatusFromData({
    required Map<String, dynamic> userData,
    required Map<String, dynamic> organizerData,
  }) {
    final directValue =
        (organizerData['status'] as String?) ??
        (userData['organizerApplicationStatus'] as String?) ??
        ((userData['organizerApplication'] as Map?)?['status'] as String?);
    return switch ((directValue ?? '').trim().toLowerCase()) {
      'draft' => OrganizerApplicationStatus.draft,
      'submitted' => OrganizerApplicationStatus.submitted,
      'under_review' => OrganizerApplicationStatus.underReview,
      'underreview' => OrganizerApplicationStatus.underReview,
      'approved' => OrganizerApplicationStatus.approved,
      'rejected' => OrganizerApplicationStatus.rejected,
      _ => OrganizerApplicationStatus.notStarted,
    };
  }

  String _friendlyAuthMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'email-already-in-use' => 'That email already has an Eventora account.',
      'invalid-email' => 'Enter a valid email address.',
      'invalid-credential' => 'Those sign-in details did not match an account.',
      'network-request-failed' =>
        'Network issue detected. Check your connection and try again.',
      'operation-not-allowed' =>
        'Email sign-in is not enabled in Firebase yet.',
      'requires-recent-login' =>
        'For security, please sign in again before deleting this account.',
      'too-many-requests' =>
        'Too many attempts were made. Please wait and try again.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' => 'No Eventora account exists for that email yet.',
      'weak-password' =>
        'Choose a stronger password with at least 6 characters.',
      'wrong-password' => 'Those sign-in details did not match an account.',
      _ => error.message ?? 'Something went wrong. Please try again.',
    };
  }

  EventoraNotificationPrefs _notificationPrefsFromData(
    Map<String, dynamic> data,
  ) {
    final raw = data['notificationPrefs'];
    if (raw is! Map) {
      return const EventoraNotificationPrefs();
    }

    return EventoraNotificationPrefs(
      pushEnabled: raw['pushEnabled'] != false,
      smsEnabled: raw['smsEnabled'] != false,
      marketingOptIn: raw['marketingOptIn'] == true,
    );
  }

  String? _normalizePhone(String? phone) {
    final value = phone?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  bool _containsRole(List<String> roles, String expected) {
    final normalized = expected.trim().toLowerCase();
    return roles.any((role) => role.trim().toLowerCase() == normalized);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    EventoraNotificationService.instance.dispose();
    super.dispose();
  }
}
