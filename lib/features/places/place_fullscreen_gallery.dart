import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Opens a simple full-screen, zoomable viewer for a set of place photos.
///
/// Reusable across the places UI: tapping any gallery image calls this with the
/// full media list and the tapped index so the user can swipe + pinch-zoom.
Future<void> showPlaceFullscreenGallery(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
}) {
  final media = urls
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .toList();
  if (media.isEmpty) {
    return Future<void>.value();
  }
  final start = initialIndex.clamp(0, media.length - 1);
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      barrierDismissible: true,
      pageBuilder: (_, _, _) =>
          PlaceFullscreenGallery(urls: media, initialIndex: start),
    ),
  );
}

class PlaceFullscreenGallery extends StatefulWidget {
  const PlaceFullscreenGallery({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<PlaceFullscreenGallery> createState() => _PlaceFullscreenGalleryState();
}

class _PlaceFullscreenGalleryState extends State<PlaceFullscreenGallery> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showCounter = widget.urls.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.urls.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                final url = widget.urls[index];
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: url.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.contain,
                            placeholder: (_, _) => const _GalleryLoading(),
                            errorWidget: (_, _, _) => const _GalleryError(),
                          )
                        : Image.asset(
                            url,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const _GalleryError(),
                          ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
          if (showCounter)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_index + 1} / ${widget.urls.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GalleryLoading extends StatelessWidget {
  const _GalleryLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 32,
      height: 32,
      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white70),
    );
  }
}

class _GalleryError extends StatelessWidget {
  const _GalleryError();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.white60, size: 40),
          SizedBox(height: 10),
          Text(
            'Photo could not be loaded',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
