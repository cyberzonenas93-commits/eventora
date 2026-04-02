import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/models/event_models.dart';
import 'art_seed.dart';
import 'mood_art_palette.dart';

/// A deterministic generative art painter that creates unique, layered
/// abstract artwork for each event based on its seed and mood.
///
/// Five layers are painted in order:
/// 1. Background radial gradient
/// 2. Organic blobs (soft bezier shapes)
/// 3. Flowing curves (smooth bezier strokes)
/// 4. Particle dots (scattered circles with glow)
/// 5. Highlight arc (focal crescent element)
class GenerativeArtPainter extends CustomPainter {
  const GenerativeArtPainter({
    required this.seed,
    required this.mood,
    this.intensity = 1.0,
    this.palette,
  });

  final int seed;
  final EventMood mood;
  final double intensity;
  final MoodArtPalette? palette;

  MoodArtPalette get _palette => palette ?? MoodArtPalette.fromMood(mood);

  @override
  void paint(Canvas canvas, Size size) {
    final pal = _palette;
    final w = size.width;
    final h = size.height;

    _paintBackground(canvas, size, pal);
    _paintOrganicBlobs(canvas, w, h, pal);
    _paintFlowingCurves(canvas, w, h, pal);
    _paintParticleDots(canvas, w, h, pal);
    _paintHighlightArc(canvas, w, h, pal);
  }

  // ── Layer 1: Background radial gradient ───────────────────────────────

  void _paintBackground(Canvas canvas, Size size, MoodArtPalette pal) {
    final cx = size.width * ArtSeed.seedRange(seed, 0, 0.2, 0.8);
    final cy = size.height * ArtSeed.seedRange(seed, 1, 0.1, 0.6);
    final radius = math.max(size.width, size.height) * 1.2;

    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(cx, cy),
        radius,
        [
          pal.base,
          Color.lerp(pal.base, pal.mid, 0.5)!,
          pal.overlay,
        ],
        [0.0, 0.5, 1.0],
      );

    canvas.drawRect(Offset.zero & size, paint);
  }

  // ── Layer 2: Organic blobs ────────────────────────────────────────────

  void _paintOrganicBlobs(
      Canvas canvas, double w, double h, MoodArtPalette pal) {
    final blobCount = 3 + ArtSeed.seedInt(seed, 10, 3); // 3–5 blobs

    for (int i = 0; i < blobCount; i++) {
      final si = 100 + i * 7;
      final cx = w * ArtSeed.seedRange(seed, si, -0.2, 1.2);
      final cy = h * ArtSeed.seedRange(seed, si + 1, -0.2, 1.2);
      final rx = w * ArtSeed.seedRange(seed, si + 2, 0.15, 0.45);
      final ry = h * ArtSeed.seedRange(seed, si + 3, 0.15, 0.45);
      final rotation = ArtSeed.seedRange(seed, si + 4, 0, math.pi * 2);
      final alpha = ArtSeed.seedRange(seed, si + 5, 0.10, 0.35) * intensity;
      final color = ArtSeed.seedColor(seed, si + 6, pal.fills);

      final path = _buildBlobPath(cx, cy, rx, ry, rotation, seed, si + 7);

      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          ArtSeed.seedRange(seed, si + 8, 20, 55),
        );

      canvas.drawPath(path, paint);
    }
  }

  Path _buildBlobPath(
    double cx,
    double cy,
    double rx,
    double ry,
    double rotation,
    int seed,
    int si,
  ) {
    final path = Path();
    const points = 6;
    final offsets = <Offset>[];

    for (int j = 0; j < points; j++) {
      final angle = rotation + (j / points) * math.pi * 2;
      final wobble = ArtSeed.seedRange(seed, si + j * 3, 0.7, 1.3);
      offsets.add(Offset(
        cx + math.cos(angle) * rx * wobble,
        cy + math.sin(angle) * ry * wobble,
      ));
    }

    path.moveTo(offsets[0].dx, offsets[0].dy);
    for (int j = 0; j < points; j++) {
      final p0 = offsets[j];
      final p1 = offsets[(j + 1) % points];
      final mx = (p0.dx + p1.dx) / 2;
      final my = (p0.dy + p1.dy) / 2;
      path.quadraticBezierTo(p0.dx, p0.dy, mx, my);
    }
    path.close();
    return path;
  }

  // ── Layer 3: Flowing curves ───────────────────────────────────────────

  void _paintFlowingCurves(
      Canvas canvas, double w, double h, MoodArtPalette pal) {
    final curveCount = 2 + ArtSeed.seedInt(seed, 20, 3); // 2–4

    for (int i = 0; i < curveCount; i++) {
      final si = 200 + i * 11;
      final color = ArtSeed.seedColor(seed, si, [pal.highlight, pal.accent, pal.pop]);
      final alpha = ArtSeed.seedRange(seed, si + 1, 0.15, 0.5) * intensity;
      final strokeWidth = ArtSeed.seedRange(seed, si + 2, 1.5, 5.0);

      final p0 = Offset(
        w * ArtSeed.seedRange(seed, si + 3, -0.1, 0.3),
        h * ArtSeed.seedRange(seed, si + 4, 0.0, 1.0),
      );
      final c1 = Offset(
        w * ArtSeed.seedRange(seed, si + 5, 0.2, 0.8),
        h * ArtSeed.seedRange(seed, si + 6, -0.2, 1.2),
      );
      final c2 = Offset(
        w * ArtSeed.seedRange(seed, si + 7, 0.2, 0.8),
        h * ArtSeed.seedRange(seed, si + 8, -0.2, 1.2),
      );
      final p1 = Offset(
        w * ArtSeed.seedRange(seed, si + 9, 0.7, 1.1),
        h * ArtSeed.seedRange(seed, si + 10, 0.0, 1.0),
      );

      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p1.dx, p1.dy);

      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, paint);
    }
  }

  // ── Layer 4: Particle dots ────────────────────────────────────────────

  void _paintParticleDots(
      Canvas canvas, double w, double h, MoodArtPalette pal) {
    final count =
        (15 + ArtSeed.seedInt(seed, 30, 16)) * intensity.ceil(); // 15–30

    for (int i = 0; i < count; i++) {
      final si = 300 + i * 5;
      final x = w * ArtSeed.seedRange(seed, si, -0.05, 1.05);
      final y = h * ArtSeed.seedRange(seed, si + 1, -0.05, 1.05);
      final r = ArtSeed.seedRange(seed, si + 2, 1.5, 7.0);
      final alpha = ArtSeed.seedRange(seed, si + 3, 0.12, 0.55) * intensity;
      final color = ArtSeed.seedColor(seed, si + 4, pal.all);

      final paint = Paint()..color = color.withValues(alpha: alpha);

      // Some dots get a glow
      if (i % 4 == 0) {
        final glowPaint = Paint()
          ..color = color.withValues(alpha: alpha * 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawCircle(Offset(x, y), r * 2.2, glowPaint);
      }

      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  // ── Layer 5: Highlight arc ────────────────────────────────────────────

  void _paintHighlightArc(
      Canvas canvas, double w, double h, MoodArtPalette pal) {
    final si = 400;
    final cx = w * ArtSeed.seedRange(seed, si, 0.2, 0.8);
    final cy = h * ArtSeed.seedRange(seed, si + 1, 0.1, 0.5);
    final radius = math.min(w, h) * ArtSeed.seedRange(seed, si + 2, 0.25, 0.55);
    final startAngle = ArtSeed.seedRange(seed, si + 3, 0, math.pi * 2);
    final sweepAngle = ArtSeed.seedRange(seed, si + 4, math.pi * 0.4, math.pi * 1.2);
    final alpha = ArtSeed.seedRange(seed, si + 5, 0.08, 0.25) * intensity;

    final paint = Paint()
      ..color = pal.highlight.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ArtSeed.seedRange(seed, si + 6, 4, 14)
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        ArtSeed.seedRange(seed, si + 7, 4, 12),
      );

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(GenerativeArtPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.mood != mood ||
      oldDelegate.intensity != intensity ||
      oldDelegate.palette != palette;
}
