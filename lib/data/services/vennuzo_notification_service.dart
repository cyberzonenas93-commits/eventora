import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/models/account_models.dart';

class VennuzoNotificationService {
  VennuzoNotificationService._();

  static final VennuzoNotificationService instance = VennuzoNotificationService._();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'vennuzo_event_updates',
    'Event updates',
    description: 'Ticket, reminder, and campaign alerts for Vennuzo.',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _firebaseEnabled = false;
  bool _initialized = false;
  bool _foregroundListenerBound = false;
  String? _lastBoundUid;
  StreamSubscription<String>? _tokenRefreshSubscription;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  Future<void> initialize({
    required bool firebaseEnabled,
  }) async {
    _firebaseEnabled = firebaseEnabled;
    if (!_firebaseEnabled || _initialized) {
      return;
    }

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _localNotifications.initialize(initializationSettings);
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    if (!_foregroundListenerBound) {
      _foregroundListenerBound = true;
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) async {
        final uid = _lastBoundUid;
        if (uid == null || token.trim().isEmpty) {
          return;
        }
        await _saveToken(uid: uid, token: token);
      });
    }

    _initialized = true;
  }

  Future<void> bindViewer(VennuzoViewer viewer) async {
    if (!_firebaseEnabled) {
      return;
    }
    await initialize(firebaseEnabled: _firebaseEnabled);

    final uid = viewer.uid;
    if (viewer.isGuest || uid == null) {
      if (_lastBoundUid != null) {
        await _clearToken(_lastBoundUid!);
      }
      _lastBoundUid = null;
      return;
    }

    _lastBoundUid = uid;
    if (!viewer.notificationPrefs.pushEnabled) {
      await _clearToken(uid);
      return;
    }

    final settings = await _requestPermissionIfNeeded();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      await _clearToken(uid);
      return;
    }

    final token = await _messaging.getToken();
    if (token == null || token.trim().isEmpty) {
      return;
    }
    await _saveToken(uid: uid, token: token);
  }

  Future<void> clearBoundToken() async {
    final uid = _lastBoundUid;
    if (uid == null) {
      return;
    }
    await _clearToken(uid);
    _lastBoundUid = null;
  }

  Future<NotificationSettings> _requestPermissionIfNeeded() async {
    final settings = await _messaging.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.notDetermined) {
      return settings;
    }
    return _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: defaultTargetPlatform == TargetPlatform.iOS,
    );
  }

  Future<void> _saveToken({
    required String uid,
    required String token,
  }) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      <String, Object?>{
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _clearToken(String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      <String, Object?>{
        'fcmToken': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) {
      return;
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
    );
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
  }
}
