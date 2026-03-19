import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GoogleMapsSecretsService {
  GoogleMapsSecretsService._();

  static final GoogleMapsSecretsService instance = GoogleMapsSecretsService._();

  static const MethodChannel _channel = MethodChannel(
    'com.vennuzo.app/maps_config',
  );

  String? _apiKey;

  Future<String?> loadApiKey() async {
    if (_apiKey != null && _apiKey!.trim().isNotEmpty) {
      return _apiKey;
    }
    if (kIsWeb) {
      return null;
    }

    final resolvedKey = await _channel.invokeMethod<String>('getApiKey');
    final trimmed = resolvedKey?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    _apiKey = trimmed;
    return _apiKey;
  }
}
