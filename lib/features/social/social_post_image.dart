import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class SocialPostImage extends StatefulWidget {
  const SocialPostImage({
    super.key,
    required this.imageUrl,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final String imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  State<SocialPostImage> createState() => _SocialPostImageState();
}

class _SocialPostImageState extends State<SocialPostImage> {
  static const _timeout = Duration(seconds: 8);

  Timer? _timer;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant SocialPostImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _timedOut = false;
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(_timeout, () {
      if (mounted) {
        setState(() => _timedOut = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final child = _timedOut
        ? _ImageFallback(
            height: widget.height,
            width: widget.width,
            message: 'Photo is taking too long to load',
          )
        : CachedNetworkImage(
            imageUrl: widget.imageUrl,
            height: widget.height,
            width: widget.width,
            fit: widget.fit,
            imageBuilder: (context, provider) {
              _timer?.cancel();
              return Image(
                image: provider,
                height: widget.height,
                width: widget.width,
                fit: widget.fit,
              );
            },
            placeholder: (_, _) =>
                _ImagePlaceholder(height: widget.height, width: widget.width),
            errorWidget: (_, _, _) => _ImageFallback(
              height: widget.height,
              width: widget.width,
              message: 'Photo could not be loaded',
            ),
          );

    if (widget.borderRadius == null) {
      return child;
    }
    return ClipRRect(borderRadius: widget.borderRadius!, child: child);
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({this.height, this.width});

  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      color: const Color(0xFF1F2937),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: Colors.white70,
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({this.height, this.width, required this.message});

  final double? height;
  final double? width;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      color: const Color(0xFF1F2937),
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: Colors.white60,
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
