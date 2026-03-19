import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/event_models.dart';
import 'google_maps_secrets_service.dart';

class VennuzoPlaceSuggestion {
  const VennuzoPlaceSuggestion({
    required this.placeId,
    required this.title,
    required this.subtitle,
    required this.fullText,
    this.distanceMeters,
  });

  final String placeId;
  final String title;
  final String subtitle;
  final String fullText;
  final int? distanceMeters;
}

class VennuzoPlaceSelection {
  const VennuzoPlaceSelection({
    required this.placeId,
    required this.venueName,
    required this.city,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String placeId;
  final String venueName;
  final String city;
  final String address;
  final double latitude;
  final double longitude;

  EventLocation toEventLocation() {
    return EventLocation(
      placeId: placeId,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

class VennuzoPlacesFailure implements Exception {
  const VennuzoPlacesFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class VennuzoPlacesService {
  VennuzoPlacesService._();

  static final VennuzoPlacesService instance = VennuzoPlacesService._();
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static final Uri _autocompleteUri = Uri.parse(
    'https://places.googleapis.com/v1/places:autocomplete',
  );

  Future<List<VennuzoPlaceSuggestion>> search(
    String query, {
    double? originLatitude,
    double? originLongitude,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.length < 2) {
      return const <VennuzoPlaceSuggestion>[];
    }

    try {
      return await _searchViaFunctions(
        trimmedQuery,
        originLatitude: originLatitude,
        originLongitude: originLongitude,
      );
    } on FirebaseFunctionsException catch (error) {
      if (kReleaseMode) {
        throw VennuzoPlacesFailure(
          error.message ??
              'Venue search is not available right now. Please try again shortly.',
        );
      }
      return _searchDirect(
        trimmedQuery,
        originLatitude: originLatitude,
        originLongitude: originLongitude,
      );
    } catch (error) {
      if (error is VennuzoPlacesFailure) {
        rethrow;
      }
      if (kReleaseMode) {
        throw const VennuzoPlacesFailure(
          'Venue search is not available right now. Please try again shortly.',
        );
      }
      return _searchDirect(
        trimmedQuery,
        originLatitude: originLatitude,
        originLongitude: originLongitude,
      );
    }
  }

  Future<VennuzoPlaceSelection> fetchSelection(String placeId) async {
    try {
      return await _fetchSelectionViaFunctions(placeId);
    } on FirebaseFunctionsException catch (error) {
      if (kReleaseMode) {
        throw VennuzoPlacesFailure(
          error.message ??
              'This location could not be loaded right now. Try another result.',
        );
      }
      return _fetchSelectionDirect(placeId);
    } catch (error) {
      if (error is VennuzoPlacesFailure) {
        rethrow;
      }
      if (kReleaseMode) {
        throw const VennuzoPlacesFailure(
          'This location could not be loaded right now. Try another result.',
        );
      }
      return _fetchSelectionDirect(placeId);
    }
  }

  Future<VennuzoPlaceSelection> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    try {
      return await _reverseGeocodeViaFunctions(
        latitude: latitude,
        longitude: longitude,
      );
    } on FirebaseFunctionsException catch (error) {
      throw VennuzoPlacesFailure(
        error.message ??
            'We could not match your current location to an address right now.',
      );
    } catch (error) {
      if (error is VennuzoPlacesFailure) {
        rethrow;
      }
      throw const VennuzoPlacesFailure(
        'We could not match your current location to an address right now.',
      );
    }
  }

  Future<String> _loadApiKey() async {
    final apiKey = await GoogleMapsSecretsService.instance.loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw const VennuzoPlacesFailure(
        'Google Maps is not configured yet. Add the local API key to enable place search.',
      );
    }
    return apiKey;
  }

  Future<List<VennuzoPlaceSuggestion>> _searchViaFunctions(
    String query, {
    double? originLatitude,
    double? originLongitude,
  }) async {
    final payload = <String, Object?>{'query': query};
    if (originLatitude != null) {
      payload['originLatitude'] = originLatitude;
    }
    if (originLongitude != null) {
      payload['originLongitude'] = originLongitude;
    }

    final result = await _functions
        .httpsCallable('autocompleteEventPlaces')
        .call(payload);

    final data = result.data;
    if (data is! Map) {
      return const <VennuzoPlaceSuggestion>[];
    }
    final suggestions = data['suggestions'];
    if (suggestions is! List) {
      return const <VennuzoPlaceSuggestion>[];
    }

    return suggestions
        .map((entry) {
          if (entry is! Map) {
            return null;
          }
          final placeId = '${entry['placeId'] ?? ''}'.trim();
          if (placeId.isEmpty) {
            return null;
          }
          return VennuzoPlaceSuggestion(
            placeId: placeId,
            title: '${entry['title'] ?? ''}'.trim(),
            subtitle: '${entry['subtitle'] ?? ''}'.trim(),
            fullText: '${entry['fullText'] ?? ''}'.trim(),
            distanceMeters: (entry['distanceMeters'] as num?)?.toInt(),
          );
        })
        .whereType<VennuzoPlaceSuggestion>()
        .toList();
  }

  Future<VennuzoPlaceSelection> _fetchSelectionViaFunctions(
    String placeId,
  ) async {
    final result = await _functions.httpsCallable('getEventPlaceDetails').call(
      <String, Object?>{'placeId': placeId},
    );

    final data = result.data;
    if (data is! Map) {
      throw const VennuzoPlacesFailure(
        'We could not load this place. Try another result.',
      );
    }

    final latitude = (data['latitude'] as num?)?.toDouble();
    final longitude = (data['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) {
      throw const VennuzoPlacesFailure(
        'This place does not include map coordinates.',
      );
    }

    final venueName = '${data['venueName'] ?? ''}'.trim();
    final address = '${data['address'] ?? ''}'.trim();
    final city = '${data['city'] ?? 'Accra'}'.trim();

    return VennuzoPlaceSelection(
      placeId: '${data['placeId'] ?? placeId}'.trim(),
      venueName: venueName.isEmpty ? _fallbackVenueName(address) : venueName,
      city: city.isEmpty ? 'Accra' : city,
      address: address.isEmpty ? '$venueName, $city' : address,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<VennuzoPlaceSelection> _reverseGeocodeViaFunctions({
    required double latitude,
    required double longitude,
  }) async {
    final result = await _functions
        .httpsCallable('reverseGeocodeEventCoordinates')
        .call(<String, Object?>{'latitude': latitude, 'longitude': longitude});

    final data = result.data;
    if (data is! Map) {
      throw const VennuzoPlacesFailure(
        'We could not match your current location to an address right now.',
      );
    }

    final resolvedLatitude = (data['latitude'] as num?)?.toDouble() ?? latitude;
    final resolvedLongitude =
        (data['longitude'] as num?)?.toDouble() ?? longitude;
    final venueName = '${data['venueName'] ?? ''}'.trim();
    final address = '${data['address'] ?? ''}'.trim();
    final city = '${data['city'] ?? 'Accra'}'.trim();

    return VennuzoPlaceSelection(
      placeId: '${data['placeId'] ?? ''}'.trim(),
      venueName: venueName.isEmpty ? _fallbackVenueName(address) : venueName,
      city: city.isEmpty ? 'Accra' : city,
      address: address.isEmpty ? '$venueName, $city' : address,
      latitude: resolvedLatitude,
      longitude: resolvedLongitude,
    );
  }

  Future<List<VennuzoPlaceSuggestion>> _searchDirect(
    String query, {
    double? originLatitude,
    double? originLongitude,
  }) async {
    final apiKey = await _loadApiKey();
    final body = <String, Object?>{
      'input': query,
      'includedRegionCodes': const ['gh'],
    };
    if (originLatitude != null && originLongitude != null) {
      body['locationBias'] = <String, Object?>{
        'circle': <String, Object?>{
          'center': <String, Object?>{
            'latitude': originLatitude,
            'longitude': originLongitude,
          },
          'radius': 50000,
        },
      };
    }

    final response = await http.post(
      _autocompleteUri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask':
            'suggestions.placePrediction.placeId,'
            'suggestions.placePrediction.text.text,'
            'suggestions.placePrediction.structuredFormat.mainText.text,'
            'suggestions.placePrediction.structuredFormat.secondaryText.text,'
            'suggestions.placePrediction.distanceMeters',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode >= 400) {
      throw VennuzoPlacesFailure(_extractErrorMessage(response.body));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const <VennuzoPlaceSuggestion>[];
    }

    final suggestions = decoded['suggestions'];
    if (suggestions is! List) {
      return const <VennuzoPlaceSuggestion>[];
    }

    return suggestions
        .map((entry) {
          if (entry is! Map) {
            return null;
          }
          final prediction = entry['placePrediction'];
          if (prediction is! Map) {
            return null;
          }

          final fullText = _stringFromNestedMap(prediction, ['text', 'text']);
          final title = _stringFromNestedMap(prediction, [
            'structuredFormat',
            'mainText',
            'text',
          ]);
          final subtitle = _stringFromNestedMap(prediction, [
            'structuredFormat',
            'secondaryText',
            'text',
          ]);
          final placeId = '${prediction['placeId'] ?? ''}'.trim();
          if (placeId.isEmpty) {
            return null;
          }

          return VennuzoPlaceSuggestion(
            placeId: placeId,
            title: title.isEmpty ? fullText : title,
            subtitle: subtitle,
            fullText: fullText.isEmpty ? title : fullText,
            distanceMeters: (prediction['distanceMeters'] as num?)?.toInt(),
          );
        })
        .whereType<VennuzoPlaceSuggestion>()
        .toList();
  }

  Future<VennuzoPlaceSelection> _fetchSelectionDirect(String placeId) async {
    final apiKey = await _loadApiKey();
    final response = await http.get(
      Uri.parse('https://places.googleapis.com/v1/places/$placeId'),
      headers: <String, String>{
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask':
            'id,displayName,formattedAddress,location,addressComponents',
      },
    );

    if (response.statusCode >= 400) {
      throw VennuzoPlacesFailure(_extractErrorMessage(response.body));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const VennuzoPlacesFailure(
        'We could not load this place. Try another result.',
      );
    }

    final location = decoded['location'];
    if (location is! Map<String, dynamic>) {
      throw const VennuzoPlacesFailure(
        'This place does not include map coordinates.',
      );
    }

    final latitude = (location['latitude'] as num?)?.toDouble();
    final longitude = (location['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) {
      throw const VennuzoPlacesFailure(
        'This place does not include map coordinates.',
      );
    }

    final displayName = _stringFromNestedMap(decoded, ['displayName', 'text']);
    final address = '${decoded['formattedAddress'] ?? ''}'.trim();
    final city = _resolveCity(decoded['addressComponents']) ?? 'Accra';

    return VennuzoPlaceSelection(
      placeId: '${decoded['id'] ?? placeId}',
      venueName: displayName.isEmpty
          ? _fallbackVenueName(address)
          : displayName,
      city: city,
      address: address.isEmpty ? '$displayName, $city' : address,
      latitude: latitude,
      longitude: longitude,
    );
  }

  String _extractErrorMessage(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = '${error['message'] ?? ''}'.trim();
          if (message.isNotEmpty) {
            return message;
          }
        }
      }
    } catch (_) {
      // Ignore invalid JSON and fall through to the default message.
    }
    return 'Google Places could not return venue results right now.';
  }

  String _stringFromNestedMap(Map<dynamic, dynamic> source, List<String> path) {
    Object? current = source;
    for (final segment in path) {
      if (current is! Map) {
        return '';
      }
      current = current[segment];
    }
    return '$current'.trim();
  }

  String? _resolveCity(Object? addressComponents) {
    if (addressComponents is! List) {
      return null;
    }

    for (final component in addressComponents) {
      if (component is! Map) {
        continue;
      }
      final types = component['types'];
      if (types is! List) {
        continue;
      }
      if (types.contains('locality')) {
        final city = '${component['longText'] ?? component['shortText'] ?? ''}'
            .trim();
        if (city.isNotEmpty) {
          return city;
        }
      }
    }

    for (final component in addressComponents) {
      if (component is! Map) {
        continue;
      }
      final types = component['types'];
      if (types is! List) {
        continue;
      }
      if (types.contains('administrative_area_level_2')) {
        final city = '${component['longText'] ?? component['shortText'] ?? ''}'
            .trim();
        if (city.isNotEmpty) {
          return city;
        }
      }
    }

    return null;
  }

  String _fallbackVenueName(String address) {
    if (address.trim().isEmpty) {
      return 'Selected venue';
    }
    final firstSegment = address.split(',').first.trim();
    return firstSegment.isEmpty ? 'Selected venue' : firstSegment;
  }
}
