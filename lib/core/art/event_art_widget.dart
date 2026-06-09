import 'package:flutter/material.dart';

import '../../domain/models/event_models.dart';
import 'art_seed.dart';
import 'generative_art_painter.dart';
import 'mood_art_palette.dart';

/// Displays unique generative artwork for an event.
///
/// The art is deterministic — the same event always produces the same visual.
/// Wrap in [RepaintBoundary] for optimal scroll performance.
class EventArtwork extends StatelessWidget {
  const EventArtwork({
    super.key,
    required this.event,
    this.height = 200,
    this.width,
    this.borderRadius,
    this.intensity = 1.0,
  });

  final EventModel event;
  final double height;
  final double? width;
  final BorderRadius? borderRadius;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final flyerAsset = event.flyerAsset?.trim();
    if (flyerAsset != null && flyerAsset.isNotEmpty) {
      // Generative art doubles as the placeholder/fallback so the slot is never
      // blank or a broken-image box while loading or on error.
      Widget fallback() => _GeneratedEventArt(
        event: event,
        width: width,
        height: height,
        intensity: intensity,
      );
      Widget flyer = flyerAsset.startsWith('http')
          ? Image.network(
              flyerAsset,
              fit: BoxFit.cover,
              width: width,
              height: height,
              // Bound decode memory — these render inside scrollable lists.
              cacheWidth: 1080,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : fallback(),
              errorBuilder: (_, _, _) => fallback(),
            )
          : Image.asset(
              flyerAsset,
              fit: BoxFit.cover,
              width: width,
              height: height,
              cacheWidth: 1080,
              errorBuilder: (_, _, _) => fallback(),
            );

      flyer = RepaintBoundary(child: flyer);
      if (borderRadius != null) {
        flyer = ClipRRect(borderRadius: borderRadius!, child: flyer);
      }
      return SizedBox(width: width, height: height, child: flyer);
    }

    Widget art = _GeneratedEventArt(
      event: event,
      width: width,
      height: height,
      intensity: intensity,
    );

    if (borderRadius != null) {
      art = ClipRRect(borderRadius: borderRadius!, child: art);
    }

    return SizedBox(width: width, height: height, child: art);
  }
}

class _GeneratedEventArt extends StatelessWidget {
  const _GeneratedEventArt({
    required this.event,
    required this.height,
    required this.intensity,
    this.width,
  });

  final EventModel event;
  final double height;
  final double? width;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final seed = ArtSeed.combine(event.id.hashCode, ArtSeed.hash(event.title));

    return RepaintBoundary(
      child: CustomPaint(
        size: Size(width ?? double.infinity, height),
        painter: GenerativeArtPainter(
          seed: seed,
          mood: event.mood,
          intensity: intensity,
        ),
      ),
    );
  }
}

/// Standalone generative art from a seed and palette (for non-event use).
class GenerativeArt extends StatelessWidget {
  const GenerativeArt({
    super.key,
    required this.seed,
    this.mood = EventMood.night,
    this.palette,
    this.height = 200,
    this.width,
    this.borderRadius,
    this.intensity = 1.0,
  });

  final int seed;
  final EventMood mood;
  final MoodArtPalette? palette;
  final double height;
  final double? width;
  final BorderRadius? borderRadius;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    Widget art = RepaintBoundary(
      child: CustomPaint(
        size: Size(width ?? double.infinity, height),
        painter: GenerativeArtPainter(
          seed: seed,
          mood: mood,
          palette: palette,
          intensity: intensity,
        ),
      ),
    );

    if (borderRadius != null) {
      art = ClipRRect(borderRadius: borderRadius!, child: art);
    }

    return SizedBox(width: width, height: height, child: art);
  }
}
