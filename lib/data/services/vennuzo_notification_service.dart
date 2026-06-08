import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/models/account_models.dart';

typedef OnNotificationOpened = void Function(RemoteMessage message);

class VennuzoNotificationService {
  VennuzoNotificationService._();

  static final VennuzoNotificationService instance =
      VennuzoNotificationService._();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'vennuzo_urgent_alerts_v2',
    'Urgent event alerts',
    description:
        'Time-sensitive ticket, event operations, reminder, and campaign alerts for Vennuzo.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _firebaseEnabled = false;
  bool _initialized = false;
  bool _foregroundListenerBound = false;
  bool _openedHandlerBound = false;
  String? _lastBoundUid;
  StreamSubscription<String>? _tokenRefreshSubscription;
  OnNotificationOpened? _onNotificationOpened;
  final Map<int, Map<String, String>> _foregroundNotificationData = {};

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  /// Call once after [initialize] with a navigator key available.
  /// When the user taps a push notification, [onOpened] is called with the message.
  void setNotificationOpenedHandler(OnNotificationOpened? onOpened) {
    _onNotificationOpened = onOpened;
  }

  Future<void> initialize({required bool firebaseEnabled}) async {
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

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    if (!_foregroundListenerBound) {
      _foregroundListenerBound = true;
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((
        token,
      ) async {
        final uid = _lastBoundUid;
        if (uid == null || token.trim().isEmpty) {
          return;
        }
        await _trySaveToken(uid: uid, token: token);
      });
    }

    if (!_openedHandlerBound) {
      _openedHandlerBound = true;
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpened);
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNotificationOpened(initialMessage);
        });
      }
    }

    _initialized = true;
  }

  void _handleNotificationOpened(RemoteMessage message) {
    final callback = _onNotificationOpened;
    if (callback != null) {
      callback(message);
    }
  }

  void _onLocalNotificationTap(NotificationResponse? response) {
    if (response?.id == null) return;
    final data = _foregroundNotificationData.remove(response!.id);
    if (data != null && data.isNotEmpty) {
      _handleNotificationOpened(RemoteMessage(data: data));
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) {
      return;
    }

    final id = notification.hashCode;
    if (message.data.isNotEmpty) {
      _foregroundNotificationData[id] = Map<String, String>.from(message.data);
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title ?? 'Vennuzo',
      notification.body ?? '',
      details,
    );
  }

  Future<void> bindViewer(
    VennuzoViewer viewer, {
    bool requestPermission = false,
  }) async {
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

    var settings = await _messaging.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      if (!requestPermission) {
        return;
      }
      settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    }
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      await _clearToken(uid);
      return;
    }

    final String? token;
    try {
      token = await _messaging.getToken();
    } on FirebaseException catch (error) {
      debugPrint(
        'Vennuzo push token unavailable: ${error.code} ${error.message ?? ''}',
      );
      return;
    }
    if (token == null || token.trim().isEmpty) {
      return;
    }
    await _trySaveToken(uid: uid, token: token);
  }

  Future<void> clearBoundToken() async {
    final uid = _lastBoundUid;
    if (uid == null) {
      return;
    }
    await _clearToken(uid);
    _lastBoundUid = null;
  }

  Future<void> _saveToken({required String uid, required String token}) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      <String, Object?>{
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _trySaveToken({
    required String uid,
    required String token,
  }) async {
    try {
      await _saveToken(uid: uid, token: token);
    } on FirebaseException catch (error) {
      debugPrint(
        'Vennuzo push token save failed: ${error.code} ${error.message ?? ''}',
      );
    }
  }

  Future<void> _clearToken(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        <String, Object?>{
          'fcmToken': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (error) {
      debugPrint(
        'Vennuzo push token clear failed: ${error.code} ${error.message ?? ''}',
      );
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
  }
}
