import 'dart:async';

import 'package:geolocator/geolocator.dart';

class EventoraLocationFailure implements Exception {
  const EventoraLocationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class EventoraLocationService {
  EventoraLocationService._();

  static final EventoraLocationService instance = EventoraLocationService._();

  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const EventoraLocationFailure(
        'Turn on location services to see events near you.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const EventoraLocationFailure(
        'Location permission was denied, so nearby events are unavailable.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const EventoraLocationFailure(
        'Location access is turned off for Eventora. Update it in system settings to see nearby events.',
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
      throw const EventoraLocationFailure(
        'We could not get your location quickly enough. Try again in a moment.',
      );
    } catch (error) {
      final message = '$error'.toLowerCase();
      if (message.contains('google play') ||
          message.contains('play services')) {
        throw const EventoraLocationFailure(
          'Nearby events are limited on this emulator because Google Play services are not installed.',
        );
      }
      throw const EventoraLocationFailure(
        'We could not access your location right now. Try again in a moment.',
      );
    }
  }
}
