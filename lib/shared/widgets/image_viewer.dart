import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Reusable thumbnail widget that loads an image from Supabase Storage.
class StorageThumbnail extends StatelessWidget {
  final String storagePath;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxFit fit;

  const StorageThumbnail({
    super.key,
    required this.storagePath,
    this.width = 56,
    this.height = 56,
    this.borderRadius,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final url = SupabaseService.getPhotoUrl(storagePath);
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(8),
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: width,
            height: height,
            color: AppColors.bgElevated,
            child: const Center(
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          width: width,
          height: height,
          color: AppColors.bgElevated,
          child: const Icon(Icons.image, color: AppColors.textMuted, size: 24),
        ),
      ),
    );
  }
}

/// Helper to download an image URL (web only).
void _downloadImage(String url, String? fileName) {
  final name = fileName ?? 'foto_inspecao.jpg';
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', name)
    ..setAttribute('target', '_blank');
  anchor.click();
}

/// Helper to share/copy URL to clipboard.
Future<void> _shareImage(BuildContext context, String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔗 Link da foto copiado!'),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// Fullscreen image viewer with zoom, pan, download, and share.
class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String? title;
  final String? heroTag;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    this.title,
    this.heroTag,
  });

  /// Opens a fullscreen viewer for a single image from Supabase Storage.
  static void openFromStorage(BuildContext context, String storagePath, {String? title}) {
    final url = SupabaseService.getPhotoUrl(storagePath);
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullScreenImageViewer(imageUrl: url, title: title, heroTag: storagePath),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// Opens a fullscreen gallery viewer for multiple images.
  static void openGallery(BuildContext context, List<String> storagePaths, {int initialIndex = 0, List<String>? titles}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) =>
            _GalleryViewer(storagePaths: storagePaths, initialIndex: initialIndex, titles: titles),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: title != null ? Text(title!, style: const TextStyle(color: Colors.white70, fontSize: 14)) : null,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            tooltip: 'Download',
            onPressed: () => _downloadImage(imageUrl, title),
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white),
            tooltip: 'Compartilhar',
            onPressed: () => _shareImage(context, imageUrl),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                    color: Colors.white,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, size: 64, color: Colors.white38),
                  SizedBox(height: 12),
                  Text('Erro ao carregar imagem', style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Internal gallery viewer with PageView for swiping between images.
class _GalleryViewer extends StatefulWidget {
  final List<String> storagePaths;
  final int initialIndex;
  final List<String>? titles;

  const _GalleryViewer({
    required this.storagePaths,
    this.initialIndex = 0,
    this.titles,
  });

  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String get _currentUrl => SupabaseService.getPhotoUrl(widget.storagePaths[_currentIndex]);

  String get _currentTitle {
    if (widget.titles != null && _currentIndex < widget.titles!.length) {
      return widget.titles![_currentIndex];
    }
    return '${_currentIndex + 1} / ${widget.storagePaths.length}';
  }

  String get _currentFileName {
    final path = widget.storagePaths[_currentIndex];
    return path.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_currentTitle, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            tooltip: 'Download',
            onPressed: () => _downloadImage(_currentUrl, _currentFileName),
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white),
            tooltip: 'Compartilhar',
            onPressed: () => _shareImage(context, _currentUrl),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_currentIndex + 1} / ${widget.storagePaths.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Photo PageView
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemCount: widget.storagePaths.length,
            itemBuilder: (context, index) {
              final url = SupabaseService.getPhotoUrl(widget.storagePaths[index]);
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5.0,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                : null,
                            color: Colors.white,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image, size: 64, color: Colors.white38),
                          SizedBox(height: 12),
                          Text('Erro ao carregar imagem', style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Navigation arrows
          if (widget.storagePaths.length > 1) ...[
            if (_currentIndex > 0)
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _navButton(Icons.chevron_left, () {
                    _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                  }),
                ),
              ),
            if (_currentIndex < widget.storagePaths.length - 1)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _navButton(Icons.chevron_right, () {
                    _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                  }),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(icon, color: Colors.white70, size: 32),
      ),
    );
  }
}
