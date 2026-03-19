import 'dart:async';

import 'package:geolocator/geolocator.dart';

class VennuzoLocationFailure implements Exception {
  const VennuzoLocationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class VennuzoLocationService {
  VennuzoLocationService._();

  static final VennuzoLocationService instance = VennuzoLocationService._();

  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const VennuzoLocationFailure(
        'Turn on location services to see events near you.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const VennuzoLocationFailure(
        'Location permission was denied, so nearby events are unavailable.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const VennuzoLocationFailure(
        'Location access is turned off for Vennuzo. Update it in system settings to see nearby events.',
      );
    }

    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return lastKnown;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } on TimeoutException {
      throw const VennuzoLocationFailure(
        'We could not get your location quickly enough. Try again in a moment.',
      );
    } catch (error) {
      final message = '$error'.toLowerCase();
      if (message.contains('google play') ||
          message.contains('play services')) {
        throw const VennuzoLocationFailure(
          'Nearby events are limited on this emulator because Google Play services are not installed.',
        );
      }
      throw const VennuzoLocationFailure(
        'We could not access your location right now. Try again in a moment.',
      );
    }
  }
}
