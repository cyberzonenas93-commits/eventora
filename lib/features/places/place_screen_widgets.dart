part of 'places_screen.dart';

class _PlaceImage extends StatelessWidget {
  const _PlaceImage({required this.url, this.thumbnail = false});

  final String? url;

  /// When true, the network image is decoded/cached at a reduced width to keep
  /// memory low for small thumbnails (gallery tiles, logos, list covers).
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    final raw = url ?? '';
    final value = raw.startsWith('/assets/') ? raw.substring(1) : raw;
    if (value.startsWith('http')) {
      final cacheWidth = thumbnail ? 320 : null;
      return CachedNetworkImage(
        imageUrl: value,
        fit: BoxFit.cover,
        memCacheWidth: cacheWidth,
        maxWidthDiskCache: cacheWidth,
        placeholder: (_, _) => const _PlaceImageLoading(),
        errorWidget: (_, _, _) => const _PlaceImageFallback(),
      );
    }
    if (value.isNotEmpty) {
      return Image.asset(
        value,
        fit: BoxFit.cover,
        cacheWidth: thumbnail ? 320 : null,
        errorBuilder: (_, _, _) => const _PlaceImageFallback(),
      );
    }
    return const _PlaceImageFallback();
  }
}

class _PlaceImageLoading extends StatelessWidget {
  const _PlaceImageLoading();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: VennuzoTheme.surfaceElevated),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// A gallery thumbnail that opens the full-screen, zoomable viewer on tap.
class _TappableGalleryImage extends StatelessWidget {
  const _TappableGalleryImage({
    required this.urls,
    required this.index,
    required this.borderRadius,
    this.thumbnail = false,
  });

  final List<String> urls;
  final int index;
  final BorderRadius borderRadius;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'View photo ${index + 1} of ${urls.length}',
      child: GestureDetector(
        onTap: () => showPlaceFullscreenGallery(
          context,
          urls: urls,
          initialIndex: index,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: _PlaceImage(
            url: index < urls.length ? urls[index] : null,
            thumbnail: thumbnail,
          ),
        ),
      ),
    );
  }
}

class _PlaceImageFallback extends StatelessWidget {
  const _PlaceImageFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [VennuzoTheme.surfaceElevated, VennuzoTheme.surfaceBright],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(child: Icon(Icons.storefront_rounded, size: 34)),
    );
  }
}

class _PlaceLogo extends StatelessWidget {
  const _PlaceLogo({required this.place, this.size = 48});

  final PlaceProfile place;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = place.logoUrl ?? place.coverUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: VennuzoTheme.borderBright),
        color: VennuzoTheme.surfaceElevated,
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? Icon(place.icon, color: context.palette.teal)
          : _PlaceImage(url: url, thumbnail: true),
    );
  }
}

List<String> _mediaForPlace(PlaceProfile place) {
  final seen = <String>{};
  final media = <String>[];
  void add(String? value) {
    final cleaned = (value ?? '').trim();
    if (cleaned.isEmpty || !seen.add(cleaned)) return;
    media.add(cleaned);
  }

  add(place.coverUrl);
  for (final url in place.galleryUrls) {
    add(url);
  }
  return media;
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: VennuzoTheme.surfaceElevated.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: VennuzoTheme.borderBright),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text(label, style: context.text.bodySmall)],
      ),
    );
  }
}

void _openPlace(BuildContext context, PlaceProfile place) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlaceDetailScreen(placeId: place.id),
    ),
  );
}
