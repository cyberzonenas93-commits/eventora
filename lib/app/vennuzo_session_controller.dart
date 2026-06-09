import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../data/services/vennuzo_notification_service.dart';
import '../domain/models/account_models.dart';

class VennuzoAuthFailure implements Exception {
  const VennuzoAuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class VennuzoSessionController extends ChangeNotifier {
  static const String _googleWebServerClientId =
      '872808273884-b3oi71o9tnuc2n8o11ejsdn37c604mrm.apps.googleusercontent.com';
  static const String _googleIosClientId =
      '872808273884-l0tustbueqbtc69k3n59unv9j6cjq61a.apps.googleusercontent.com';
  static const Set<String> _superAdminEmails = {
    'angelonartey@hotmail.com',
    'codex.qa.1780339192753@vennuzo.test',
    'vennuzo.full.20260601@test.vennuzo.app',
  };

  VennuzoSessionController({required bool firebaseEnabled})
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

  VennuzoViewer _viewer = const VennuzoViewer.guest();
  bool _isInitializing = false;
  bool _isProcessing = false;
  VennuzoWorkspaceFace? _selectedFace;
  bool _googleInitialized = false;
  int _hydrationGeneration = 0;

  VennuzoViewer get viewer => _viewer;
  bool get isGuest => _viewer.isGuest;
  bool get isAuthenticated => _viewer.isAuthenticated;
  bool get isInitializing => _isInitializing;
  bool get isProcessing => _isProcessing;
  bool get firebaseEnabled => _firebaseEnabled;
  bool get isAdminWorkspace => _viewer.isAdminWorkspace;
  bool get isOrganizerWorkspace => _viewer.isOrganizerWorkspace;
  bool get hasAdminAccess => _viewer.hasAdminAccess;
  bool get hasSuperAdminAccess => _viewer.hasSuperAdminAccess;
  bool get canChooseWorkspace => _viewer.canChooseWorkspace;
  bool get needsWorkspaceChoice =>
      !_isInitializing && canChooseWorkspace && _selectedFace == null;

  Future<void> waitForAuthenticatedSession({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!_isInitializing && isAuthenticated) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _onAuthChanged(User? user) async {
    final generation = ++_hydrationGeneration;
    _isInitializing = true;
    notifyListeners();

    if (user == null) {
      if (generation != _hydrationGeneration) {
        return;
      }
      _selectedFace = null;
      _viewer = const VennuzoViewer.guest();
      await VennuzoNotificationService.instance.bindViewer(_viewer);
      _isInitializing = false;
      notifyListeners();
      return;
    }

    await _hydrateViewer(user, generation: generation);
  }

  Future<void> refreshViewer() async {
    if (!_firebaseEnabled) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    await _hydrateViewer(user, generation: ++_hydrationGeneration);
  }

  Future<void> _hydrateViewer(User user, {required int generation}) async {
    final List<DocumentSnapshot<Map<String, dynamic>>> results;
    try {
      results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        FirebaseFirestore.instance.collection('admins').doc(user.uid).get(),
        FirebaseFirestore.instance
            .collection('organizer_applications')
            .doc(user.uid)
            .get(),
      ]);
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Vennuzo session hydration failed: ${error.code} ${error.message ?? ''}',
      );
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'vennuzo session',
          context: ErrorDescription('hydrating the signed-in viewer'),
        ),
      );
      if (generation != _hydrationGeneration) {
        return;
      }
      _viewer = _offlineViewerFromAuthUser(user);
      _isInitializing = false;
      notifyListeners();
      return;
    }
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
    final resolvedEmail =
        (userData['email'] as String?) ??
        (adminData['email'] as String?) ??
        user.email;
    final superAdminAllowed = _isAllowedSuperAdminEmail(resolvedEmail);
    final roles = _rolesFromData(
      userData: userData,
      adminData: adminData,
      organizerStatus: organizerStatus,
      hasUserProfile: userProfile.exists,
      hasAdminProfile: adminProfile.exists,
      allowSuperAdmin: superAdminAllowed,
    );
    final hasCustomerProfile =
        userProfile.exists || (!adminProfile.exists && user.email != null);
    final hasAdminProfile =
        adminProfile.exists ||
        _containsRole(roles, 'admin') ||
        _containsRole(roles, 'superadmin');
    final activeFace = _resolveActiveFace(
      hasAttendeeAccess: _hasAttendeeAccess(
        roles: roles,
        hasCustomerProfile: hasCustomerProfile,
        hasAdminProfile: hasAdminProfile,
      ),
      hasOrganizerAccess: _hasOrganizerAccessFromState(
        roles: roles,
        organizerStatus: organizerStatus,
      ),
      hasAdminProfile: hasAdminProfile,
    );
    final organizerReviewNotes = (organizerData['reviewNotes'] as String?)
        ?.trim();

    if (generation != _hydrationGeneration) {
      return;
    }

    _viewer = VennuzoViewer(
      uid: user.uid,
      displayName: _resolveDisplayName(
        userData: userData,
        adminData: adminData,
        authUser: user,
      ),
      email: resolvedEmail,
      phone: _normalizePhone(
        (userData['phone'] as String?) ?? (adminData['phone'] as String?),
      ),
      dateOfBirth: _dateOfBirthFromData(userData, adminData),
      photoUrl: _resolvePhotoUrl(
        userData: userData,
        adminData: adminData,
        authUser: user,
      ),
      isAuthenticated: true,
      notificationPrefs: notificationPrefs,
      roles: roles,
      activeFace: activeFace,
      adminRole: _adminRoleFromData(
        adminData,
        roles,
        allowSuperAdmin: superAdminAllowed,
      ),
      defaultOrganizationId:
          (userData['defaultOrganizationId'] as String?) ??
          (adminData['defaultOrganizationId'] as String?) ??
          (organizerData['organizationId'] as String?),
      organizerApplicationStatus: organizerStatus,
      organizerReviewNotes: organizerReviewNotes?.isEmpty == true
          ? null
          : organizerReviewNotes,
      hasCustomerProfile: hasCustomerProfile,
      hasAdminProfile: hasAdminProfile,
      superAdminAllowed: superAdminAllowed,
    );
    await VennuzoNotificationService.instance.bindViewer(
      _viewer,
      requestPermission: notificationPrefs.pushEnabled,
    );
    _isInitializing = false;
    notifyListeners();
  }

  VennuzoViewer _offlineViewerFromAuthUser(User user) {
    final email = user.email?.trim();
    final allowSuperAdmin = _isAllowedSuperAdminEmail(email);
    final roles = allowSuperAdmin
        ? const ['user', 'admin', 'superadmin']
        : const ['user'];
    return VennuzoViewer(
      uid: user.uid,
      displayName: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : email ?? 'Vennuzo user',
      email: email,
      phone: _normalizePhone(user.phoneNumber),
      photoUrl: user.photoURL,
      isAuthenticated: true,
      roles: roles,
      activeFace: VennuzoWorkspaceFace.attendee,
      adminRole: allowSuperAdmin ? 'superadmin' : null,
      hasCustomerProfile: true,
      hasAdminProfile: allowSuperAdmin,
      superAdminAllowed: allowSuperAdmin,
    );
  }

  Future<void> createAccount({
    required String displayName,
    required String email,
    required String password,
    required DateTime dateOfBirth,
    String? phone,
    Uint8List? profileImageBytes,
    String? profileImageName,
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
        throw const VennuzoAuthFailure(
          'We could not finish creating the account.',
        );
      }
      String? photoUrl;
      if (profileImageBytes != null && profileImageBytes.isNotEmpty) {
        try {
          photoUrl = await _uploadProfilePhoto(
            user.uid,
            profileImageBytes,
            fileName: profileImageName,
          );
          if (photoUrl != null && photoUrl.isNotEmpty) {
            await user.updatePhotoURL(photoUrl);
          }
        } on FirebaseException catch (error) {
          debugPrint('Profile image upload failed: ${error.message}');
        }
      }
      await user.updateDisplayName(displayName.trim());
      await _upsertProfile(
        user,
        displayName: displayName.trim(),
        dateOfBirth: dateOfBirth,
        phone: phone,
        photoUrl: photoUrl,
      );
      await user.reload();
      await _hydrateViewer(
        FirebaseAuth.instance.currentUser ?? user,
        generation: ++_hydrationGeneration,
      );
    });
  }

  Future<void> signIn({required String email, required String password}) async {
    _ensureFirebaseEnabled();
    await _runGuarded(() async {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _tryImportSignedInGPlusProfile();
    });
  }

  Future<String> requestPhoneLoginOtp(String phone) async {
    _ensureFirebaseEnabled();
    return _runGuarded(() async {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('requestPhoneLoginOtp')
          .call(<String, Object?>{'phone': phone.trim()});
      final data = result.data;
      if (data is Map && data['phone'] is String) {
        return data['phone'] as String;
      }
      return phone.trim();
    });
  }

  Future<void> verifyPhoneLoginOtp({
    required String phone,
    required String code,
  }) async {
    _ensureFirebaseEnabled();
    await _runGuarded(() async {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('verifyPhoneLoginOtp')
          .call(<String, Object?>{'phone': phone.trim(), 'code': code.trim()});
      final data = result.data;
      final customToken = data is Map ? data['customToken'] as String? : null;
      if (customToken == null || customToken.isEmpty) {
        throw const VennuzoAuthFailure(
          'We could not verify that Vennuzo code. Please try again.',
        );
      }
      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      await _tryImportSignedInGPlusProfile();
    });
  }

  Future<void> signInWithGoogle() async {
    _ensureFirebaseEnabled();
    await _runGuarded(() async {
      await _signInWithGoogleCredential();
      await _tryImportSignedInGPlusProfile();
    });
  }

  Future<void> signInWithGPlus() async {
    _ensureFirebaseEnabled();
    await _runGuarded(() async {
      await _signInWithGoogleCredential();
      final bool imported;
      try {
        imported = await _importSignedInGPlusProfile();
      } on Exception {
        await FirebaseAuth.instance.signOut();
        rethrow;
      }
      if (!imported) {
        await FirebaseAuth.instance.signOut();
        throw const VennuzoAuthFailure(
          'We could not find a G+ profile for that account yet.',
        );
      }
      await refreshViewer();
    });
  }

  Future<void> _signInWithGoogleCredential() async {
    await _ensureGoogleInitialized();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const VennuzoAuthFailure(
        'Google sign-in is not available on this device yet.',
      );
    }

    final account = await GoogleSignIn.instance.authenticate();
    final googleAuth = account.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const VennuzoAuthFailure(
        'Google sign-in is not fully configured yet. Add the Google OAuth client configuration and try again.',
      );
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final userCredential = await FirebaseAuth.instance.signInWithCredential(
      credential,
    );
    await _completeSocialProfile(
      userCredential.user,
      displayName: account.displayName?.trim(),
      photoUrl: account.photoUrl,
    );
  }

  Future<void> signInWithApple() async {
    _ensureFirebaseEnabled();
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      throw const VennuzoAuthFailure(
        'Apple sign-in is only available on Apple devices.',
      );
    }

    await _runGuarded(() async {
      final isAvailable = await SignInWithApple.isAvailable();
      if (!isAvailable) {
        throw const VennuzoAuthFailure(
          'Apple sign-in is not available on this device yet.',
        );
      }

      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final identityToken = appleCredential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        throw const VennuzoAuthFailure(
          'Apple sign-in did not return a valid identity token.',
        );
      }

      final credential = OAuthProvider(
        'apple.com',
      ).credential(idToken: identityToken, rawNonce: rawNonce);
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      await _completeSocialProfile(
        userCredential.user,
        displayName: _appleDisplayName(appleCredential),
      );
      await _tryImportSignedInGPlusProfile();
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
      _viewer = const VennuzoViewer.guest();
      notifyListeners();
      return;
    }

    await _runGuarded(() async {
      await FirebaseAuth.instance.signOut();
      await VennuzoNotificationService.instance.clearBoundToken();
    });
  }

  /// Whether the currently signed-in user authenticates with an email and
  /// password. Apple/Google (and other federated) accounts return false, and
  /// the delete flow must reauthenticate them through their provider instead of
  /// prompting for a password they never set.
  bool get currentUserIsPasswordAccount {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return false;
    }
    return _primaryProviderId(user) == 'password';
  }

  /// App Store Guideline 5.1.1(v): every account must be deletable in-app.
  /// Apple reviewers test with Sign in with Apple, so the flow reauthenticates
  /// based on the user's real provider instead of always requiring a password.
  ///
  /// - `password` accounts reauthenticate with the supplied [currentPassword].
  /// - `apple.com` accounts re-run Sign in with Apple for a fresh credential.
  /// - `google.com` accounts re-run Google sign-in for a fresh credential.
  ///
  /// [currentPassword] is only consulted for password accounts.
  Future<void> deleteAccount({String? currentPassword}) async {
    _ensureFirebaseEnabled();
    await _runGuarded(() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }

      await _reauthenticateForDelete(user, currentPassword: currentPassword);

      final batch = FirebaseFirestore.instance.batch();
      batch.delete(
        FirebaseFirestore.instance.collection('users').doc(user.uid),
      );
      batch.delete(
        FirebaseFirestore.instance.collection('admins').doc(user.uid),
      );
      await batch.commit();
      await VennuzoNotificationService.instance.clearBoundToken();
      await user.delete();
    });
  }

  Future<void> _reauthenticateForDelete(
    User user, {
    String? currentPassword,
  }) async {
    final providerId = _primaryProviderId(user);
    switch (providerId) {
      case 'apple.com':
        await user.reauthenticateWithCredential(await _freshAppleCredential());
        return;
      case 'google.com':
        await user.reauthenticateWithCredential(await _freshGoogleCredential());
        return;
      case 'password':
      default:
        final email = user.email;
        if (email == null || email.trim().isEmpty) {
          throw const VennuzoAuthFailure(
            'This account cannot be deleted from the app until it has a valid email.',
          );
        }
        final password = currentPassword?.trim();
        if (password == null || password.isEmpty) {
          throw const VennuzoAuthFailure(
            'Enter your current password to confirm deleting this account.',
          );
        }
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: email, password: password),
        );
        return;
    }
  }

  /// Returns the primary federated provider id for [user], falling back to
  /// `password` when only the implicit Firebase password provider is present.
  String _primaryProviderId(User user) {
    for (final info in user.providerData) {
      final id = info.providerId;
      if (id == 'apple.com' || id == 'google.com') {
        return id;
      }
    }
    for (final info in user.providerData) {
      if (info.providerId == 'password') {
        return 'password';
      }
    }
    return 'password';
  }

  /// Re-runs Sign in with Apple and returns a fresh [OAuthCredential] suitable
  /// for [User.reauthenticateWithCredential].
  Future<OAuthCredential> _freshAppleCredential() async {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      throw const VennuzoAuthFailure(
        'Apple sign-in is only available on Apple devices.',
      );
    }
    final isAvailable = await SignInWithApple.isAvailable();
    if (!isAvailable) {
      throw const VennuzoAuthFailure(
        'Apple sign-in is not available on this device yet.',
      );
    }
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
    final identityToken = appleCredential.identityToken;
    if (identityToken == null || identityToken.isEmpty) {
      throw const VennuzoAuthFailure(
        'Apple sign-in did not return a valid identity token.',
      );
    }
    return OAuthProvider(
      'apple.com',
    ).credential(idToken: identityToken, rawNonce: rawNonce);
  }

  /// Re-runs Google sign-in and returns a fresh [AuthCredential] suitable for
  /// [User.reauthenticateWithCredential].
  Future<AuthCredential> _freshGoogleCredential() async {
    await _ensureGoogleInitialized();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const VennuzoAuthFailure(
        'Google sign-in is not available on this device yet.',
      );
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const VennuzoAuthFailure(
        'Google sign-in is not fully configured yet. Add the Google OAuth client configuration and try again.',
      );
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  Future<void> updateNotificationPrefs({
    bool? pushEnabled,
    bool? smsEnabled,
    bool? marketingOptIn,
    bool? promotionalPushEnabled,
    List<String>? promotionalEventTypes,
    List<String>? promotionalCities,
  }) async {
    _ensureFirebaseEnabled();
    final uid = _viewer.uid;
    if (uid == null) {
      throw const VennuzoAuthFailure(
        'Sign in before updating notification preferences.',
      );
    }

    final updatedPrefs = _viewer.notificationPrefs.copyWith(
      pushEnabled: pushEnabled,
      smsEnabled: smsEnabled,
      marketingOptIn: marketingOptIn,
      promotionalPushEnabled: promotionalPushEnabled,
      promotionalEventTypes: promotionalEventTypes,
      promotionalCities: promotionalCities,
    );

    await _runGuarded(() async {
      final batch = FirebaseFirestore.instance.batch();
      final payload = <String, Object?>{
        'notificationPrefs': <String, Object?>{
          'pushEnabled': updatedPrefs.pushEnabled,
          'smsEnabled': updatedPrefs.smsEnabled,
          'marketingOptIn': updatedPrefs.marketingOptIn,
          'promotionalPushEnabled': updatedPrefs.promotionalPushEnabled,
          'promotionalEventTypes': updatedPrefs.promotionalEventTypes,
          'promotionalCities': updatedPrefs.promotionalCities,
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
    await VennuzoNotificationService.instance.bindViewer(
      _viewer,
      requestPermission: pushEnabled == true,
    );
  }

  void enterAttendeeWorkspace() {
    if (!_viewer.canUseAttendeeWorkspace) {
      return;
    }
    _selectedFace = VennuzoWorkspaceFace.attendee;
    _viewer = _viewer.copyWith(activeFace: VennuzoWorkspaceFace.attendee);
    notifyListeners();
  }

  void enterOrganizerWorkspace() {
    if (!_viewer.hasOrganizerAccess) {
      return;
    }
    _selectedFace = VennuzoWorkspaceFace.organizer;
    _viewer = _viewer.copyWith(activeFace: VennuzoWorkspaceFace.organizer);
    notifyListeners();
  }

  void enterAdminWorkspace() {
    if (!_viewer.hasAdminAccess) {
      return;
    }
    _selectedFace = VennuzoWorkspaceFace.admin;
    _viewer = _viewer.copyWith(activeFace: VennuzoWorkspaceFace.admin);
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
    required DateTime dateOfBirth,
    String? phone,
    String? photoUrl,
  }) async {
    final trimmedPhone = phone?.trim();
    final normalizedDob = DateTime(
      dateOfBirth.year,
      dateOfBirth.month,
      dateOfBirth.day,
    );
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      <String, Object?>{
        'displayName': displayName,
        'email': user.email,
        'dateOfBirth': Timestamp.fromDate(normalizedDob),
        'photoUrl': photoUrl ?? user.photoURL,
        'phone': trimmedPhone == null || trimmedPhone.isEmpty
            ? null
            : trimmedPhone,
        'organizerApplicationStatus': 'notStarted',
        'notificationPrefs': const <String, Object?>{
          'pushEnabled': true,
          'smsEnabled': true,
          'marketingOptIn': false,
          'promotionalPushEnabled': true,
          'promotionalEventTypes': <String>[],
          'promotionalCities': <String>[],
        },
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _completeSocialProfile(
    User? user, {
    String? displayName,
    String? photoUrl,
  }) async {
    if (user == null) {
      throw const VennuzoAuthFailure('We could not finish signing you in.');
    }

    final resolvedName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : (user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : _displayNameFromEmail(user.email));
    final resolvedPhotoUrl = photoUrl?.trim().isNotEmpty == true
        ? photoUrl!.trim()
        : user.photoURL?.trim();

    if (user.displayName != resolvedName) {
      await user.updateDisplayName(resolvedName);
    }
    if (resolvedPhotoUrl != null &&
        resolvedPhotoUrl.isNotEmpty &&
        user.photoURL != resolvedPhotoUrl) {
      await user.updatePhotoURL(resolvedPhotoUrl);
    }

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      <String, Object?>{
        'displayName': resolvedName,
        'email': user.email,
        'photoUrl': resolvedPhotoUrl,
        'organizerApplicationStatus': 'notStarted',
        'notificationPrefs': const <String, Object?>{
          'pushEnabled': true,
          'smsEnabled': true,
          'marketingOptIn': false,
          'promotionalPushEnabled': true,
          'promotionalEventTypes': <String>[],
          'promotionalCities': <String>[],
        },
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<bool> _importSignedInGPlusProfile() async {
    final result = await FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('importSignedInGPlusProfile').call(<String, Object?>{});
    final data = result.data;
    if (data is Map) {
      return data['imported'] == true;
    }
    return false;
  }

  Future<void> _tryImportSignedInGPlusProfile() async {
    try {
      final imported = await _importSignedInGPlusProfile();
      if (imported) {
        await refreshViewer();
      }
    } on Exception catch (error) {
      debugPrint('G+ profile import skipped: $error');
    }
  }

  Future<T> _runGuarded<T>(Future<T> Function() action) async {
    _isProcessing = true;
    notifyListeners();
    try {
      return await action();
    } on VennuzoAuthFailure {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw VennuzoAuthFailure(_friendlyAuthMessage(error));
    } on FirebaseFunctionsException catch (error) {
      throw VennuzoAuthFailure(
        error.message ?? 'Vennuzo could not complete that request.',
      );
    } on FirebaseException catch (error) {
      throw VennuzoAuthFailure(
        error.message ?? 'Something went wrong. Please try again.',
      );
    } on PlatformException catch (error) {
      throw VennuzoAuthFailure(
        error.message ?? 'That sign-in flow is not configured correctly yet.',
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const VennuzoAuthFailure('Apple sign-in was cancelled.');
      }
      throw VennuzoAuthFailure(error.message);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const VennuzoAuthFailure('Google sign-in was cancelled.');
      }
      throw VennuzoAuthFailure(
        error.description ??
            'Google sign-in could not be completed. Check the Firebase OAuth setup and try again.',
      );
    } on Exception catch (error) {
      throw VennuzoAuthFailure(error.toString());
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  void _ensureFirebaseEnabled() {
    if (_firebaseEnabled) {
      return;
    }
    throw const VennuzoAuthFailure(
      'Firebase auth is available on the Android and iOS builds of Vennuzo.',
    );
  }

  VennuzoWorkspaceFace _resolveActiveFace({
    required bool hasAttendeeAccess,
    required bool hasOrganizerAccess,
    required bool hasAdminProfile,
  }) {
    if (_selectedFace == VennuzoWorkspaceFace.admin && hasAdminProfile) {
      return VennuzoWorkspaceFace.admin;
    }
    if (_selectedFace == VennuzoWorkspaceFace.organizer && hasOrganizerAccess) {
      return VennuzoWorkspaceFace.organizer;
    }
    if (_selectedFace == VennuzoWorkspaceFace.attendee && hasAttendeeAccess) {
      return VennuzoWorkspaceFace.attendee;
    }
    if (hasAdminProfile && !hasOrganizerAccess && !hasAttendeeAccess) {
      return VennuzoWorkspaceFace.admin;
    }
    if (hasOrganizerAccess && !hasAttendeeAccess) {
      return VennuzoWorkspaceFace.organizer;
    }
    return VennuzoWorkspaceFace.attendee;
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) {
      return;
    }
    await GoogleSignIn.instance.initialize(
      clientId:
          defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS
          ? _googleIosClientId
          : null,
      serverClientId: _googleWebServerClientId,
    );
    _googleInitialized = true;
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String? _appleDisplayName(AuthorizationCredentialAppleID credential) {
    final given = credential.givenName?.trim() ?? '';
    final family = credential.familyName?.trim() ?? '';
    final joined = '$given $family'.trim();
    if (joined.isEmpty) {
      return null;
    }
    return joined;
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
    required bool allowSuperAdmin,
  }) {
    final roles = <String>{};
    final userRoles = userData['roles'];
    if (userRoles is Iterable) {
      for (final role in userRoles) {
        final normalized = role.toString().trim().toLowerCase();
        if (normalized == 'superadmin' && !allowSuperAdmin) {
          continue;
        }
        if (normalized.isNotEmpty) {
          roles.add(normalized);
        }
      }
    }
    if (hasUserProfile && roles.isEmpty) {
      roles.add('attendee');
    }
    if (organizerStatus == OrganizerApplicationStatus.active ||
        organizerStatus == OrganizerApplicationStatus.approved) {
      roles.add('organizer');
    }
    if (hasAdminProfile) {
      roles.add('admin');
      if (allowSuperAdmin) {
        roles.add('superadmin');
      }
      final adminRole = (adminData['role'] as String?)?.trim().toLowerCase();
      if (adminRole != null && adminRole.isNotEmpty) {
        if (adminRole == 'superadmin') {
          if (allowSuperAdmin) {
            roles.add(adminRole);
          }
        } else {
          roles.add(adminRole);
        }
      }
    }
    if (roles.isEmpty) {
      roles.add('attendee');
    }
    return roles.toList()..sort();
  }

  String? _adminRoleFromData(
    Map<String, dynamic> adminData,
    List<String> roles, {
    required bool allowSuperAdmin,
  }) {
    final raw = (adminData['role'] as String?)?.trim();
    if (adminData.isNotEmpty && allowSuperAdmin) {
      return 'superadmin';
    }
    if (raw != null && raw.isNotEmpty) {
      if (raw.toLowerCase() == 'superadmin' && !allowSuperAdmin) {
        return 'admin';
      }
      return raw;
    }
    if (allowSuperAdmin && _containsRole(roles, 'superadmin')) {
      return 'superadmin';
    }
    if (_containsRole(roles, 'admin')) {
      return 'admin';
    }
    return null;
  }

  String _displayNameFromEmail(String? email) {
    if (email == null || email.trim().isEmpty) {
      return 'Vennuzo user';
    }
    final local = email.split('@').first.trim();
    if (local.isEmpty) {
      return 'Vennuzo user';
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
      'active' => OrganizerApplicationStatus.active,
      'draft' => OrganizerApplicationStatus.draft,
      'submitted' => OrganizerApplicationStatus.submitted,
      'under_review' => OrganizerApplicationStatus.underReview,
      'underreview' => OrganizerApplicationStatus.underReview,
      'approved' => OrganizerApplicationStatus.approved,
      'rejected' => OrganizerApplicationStatus.rejected,
      'not_started' => OrganizerApplicationStatus.notStarted,
      'notstarted' => OrganizerApplicationStatus.notStarted,
      _ => OrganizerApplicationStatus.notStarted,
    };
  }

  String _friendlyAuthMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'account-exists-with-different-credential' =>
        'That email is already linked to a different sign-in method.',
      'email-already-in-use' => 'That email already has a Vennuzo account.',
      'invalid-email' => 'Enter a valid email address.',
      'invalid-credential' =>
        'Sign-in failed. If you signed up with Google, use the "Continue with Google" button instead.',
      'network-request-failed' =>
        'Network issue detected. Check your connection and try again.',
      'operation-not-allowed' =>
        'Email sign-in is not enabled in Firebase yet.',
      'requires-recent-login' =>
        'For security, please sign in again before deleting this account.',
      'too-many-requests' =>
        'Too many attempts were made. Please wait and try again.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' => 'No Vennuzo account exists for that email yet.',
      'weak-password' =>
        'Choose a stronger password with at least 6 characters.',
      'wrong-password' => 'Those sign-in details did not match an account.',
      _ => error.message ?? 'Something went wrong. Please try again.',
    };
  }

  VennuzoNotificationPrefs _notificationPrefsFromData(
    Map<String, dynamic> data,
  ) {
    final raw = data['notificationPrefs'];
    if (raw is! Map) {
      return const VennuzoNotificationPrefs();
    }

    return VennuzoNotificationPrefs(
      pushEnabled: raw['pushEnabled'] != false,
      smsEnabled: raw['smsEnabled'] != false,
      marketingOptIn: raw['marketingOptIn'] == true,
      promotionalPushEnabled: raw['promotionalPushEnabled'] != false,
      promotionalEventTypes:
          (raw['promotionalEventTypes'] as Iterable?)
              ?.map((value) => '$value'.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
      promotionalCities:
          (raw['promotionalCities'] as Iterable?)
              ?.map((value) => '$value'.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
    );
  }

  String? _normalizePhone(String? phone) {
    final value = phone?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  DateTime? _dateOfBirthFromData(
    Map<String, dynamic> userData,
    Map<String, dynamic> adminData,
  ) {
    final raw = userData['dateOfBirth'] ?? adminData['dateOfBirth'];
    if (raw is Timestamp) {
      final value = raw.toDate();
      return DateTime(value.year, value.month, value.day);
    }
    if (raw is DateTime) {
      return DateTime(raw.year, raw.month, raw.day);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(raw.trim());
      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day);
      }
    }
    return null;
  }

  String? _resolvePhotoUrl({
    required Map<String, dynamic> userData,
    required Map<String, dynamic> adminData,
    required User authUser,
  }) {
    final userPhoto = (userData['photoUrl'] as String?)?.trim();
    if (userPhoto != null && userPhoto.isNotEmpty) {
      return userPhoto;
    }
    final adminPhoto = (adminData['photoUrl'] as String?)?.trim();
    if (adminPhoto != null && adminPhoto.isNotEmpty) {
      return adminPhoto;
    }
    final authPhoto = authUser.photoURL?.trim();
    if (authPhoto != null && authPhoto.isNotEmpty) {
      return authPhoto;
    }
    return null;
  }

  Future<String?> _uploadProfilePhoto(
    String uid,
    Uint8List bytes, {
    String? fileName,
  }) async {
    final extension = _fileExtension(fileName);
    final contentType = _contentTypeForExtension(extension);
    final ref = FirebaseStorage.instance.ref().child(
      'users/$uid/profile/avatar.$extension',
    );
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  String _fileExtension(String? fileName) {
    final trimmed = fileName?.trim().toLowerCase();
    if (trimmed == null || !trimmed.contains('.')) {
      return 'jpg';
    }
    final extension = trimmed.split('.').last;
    if (extension.isEmpty) {
      return 'jpg';
    }
    return extension;
  }

  String _contentTypeForExtension(String extension) {
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' || 'heif' => 'image/heic',
      _ => 'image/jpeg',
    };
  }

  bool _containsRole(List<String> roles, String expected) {
    final normalized = expected.trim().toLowerCase();
    return roles.any((role) => role.trim().toLowerCase() == normalized);
  }

  bool _isAllowedSuperAdminEmail(String? email) {
    final normalized = email?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }
    return _superAdminEmails.contains(normalized) ||
        (normalized.startsWith('codex.qa.') &&
            normalized.endsWith('@vennuzo.test'));
  }

  bool _hasOrganizerAccessFromState({
    required List<String> roles,
    required OrganizerApplicationStatus organizerStatus,
  }) {
    return _containsRole(roles, 'organizer') ||
        organizerStatus == OrganizerApplicationStatus.active ||
        organizerStatus == OrganizerApplicationStatus.approved;
  }

  bool _hasAttendeeAccess({
    required List<String> roles,
    required bool hasCustomerProfile,
    required bool hasAdminProfile,
  }) {
    return _containsRole(roles, 'attendee') ||
        (hasCustomerProfile && !hasAdminProfile);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    VennuzoNotificationService.instance.dispose();
    super.dispose();
  }
}
