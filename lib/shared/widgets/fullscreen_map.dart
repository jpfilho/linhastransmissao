import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// A fullscreen map overlay with zoom controls and close button.
class FullScreenMap extends StatelessWidget {
  final LatLng center;
  final double zoom;
  final List<Widget> children;
  final String? title;

  const FullScreenMap({
    super.key,
    required this.center,
    required this.children,
    this.zoom = 15,
    this.title,
  });

  /// Opens a fullscreen map dialog.
  static void open(
    BuildContext context, {
    required LatLng center,
    required List<Widget> children,
    double zoom = 15,
    String? title,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) => FullScreenMap(
          center: center,
          children: children,
          zoom: zoom,
          title: title,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: zoom,
              minZoom: 3,
              maxZoom: 18,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
                userAgentPackageName: 'com.inspecao.torres',
              ),
              ...children,
            ],
          ),
          // Close button
          Positioned(
            top: 16,
            left: 16,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.close, color: Colors.white, size: 20),
                      if (title != null) ...[
                        const SizedBox(width: 8),
                        Text(title!, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Map type label
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
              child: const Text('Satélite', style: TextStyle(color: Colors.white70, fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small fullscreen button overlay to place on top of any map widget.
class MapFullscreenButton extends StatelessWidget {
  final VoidCallback onTap;

  const MapFullscreenButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.fullscreen, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}
