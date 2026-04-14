import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../../shared/models/linha.dart';
import '../../../features/torres/models/torre.dart';
import '../../../features/fotos/models/foto.dart';

class InspectionMapView extends StatefulWidget {
  const InspectionMapView({super.key});

  @override
  State<InspectionMapView> createState() => _InspectionMapViewState();
}

class _InspectionMapViewState extends State<InspectionMapView> {
  final MapController _mapController = MapController();
  String? _selectedLinhaId;
  Torre? _selectedTorre;
  bool _showPhotos = true;
  bool _showLines = true;

  List<Torre> _allTowers = [];
  List<Linha> _linhas = [];
  List<Foto> _allFotos = [];
  bool _isLoading = true;

  // Caches for map rendering
  List<Marker> _cachedTowerMarkers = [];
  List<Marker> _cachedPhotoMarkers = [];
  List<Polyline> _cachedPolylines = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      SupabaseService.getTorres(),
      SupabaseService.getLinhas(),
      SupabaseService.getFotosForMap(),
    ]);
    setState(() {
      _allTowers = results[0] as List<Torre>;
      _linhas = results[1] as List<Linha>
        ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      _allFotos = results[2] as List<Foto>;
      _isLoading = false;
    });
    
    _recalculateLayers();
  }

  void _recalculateLayers() {
    var towers = _allTowers;
    if (_selectedLinhaId != null) {
      towers = towers.where((t) => t.linhaId == _selectedLinhaId).toList();
    }

    _cachedPolylines = _buildPolylines();
    _cachedPhotoMarkers = _buildPhotoMarkers(towers);
    _updateTowerMarkers(towers);
  }

  void _updateTowerMarkers(List<Torre> towers) {
    _cachedTowerMarkers = towers.map((torre) {
      final color = AppColors.getCriticalityColor(torre.criticidadeAtual);
      final isSelected = _selectedTorre?.id == torre.id;
      return Marker(
        point: LatLng(torre.latitude, torre.longitude),
        width: isSelected ? 44 : 36,
        height: isSelected ? 44 : 36,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedTorre = torre;
              _updateTowerMarkers(_filteredTowers); // Refresh just markers on tap
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : color.withValues(alpha: 0.5),
                width: isSelected ? 3 : 2,
              ),
              // REMOVIDO: BoxShadow causava uma extrema lentidao (stuttering) ao dar zoom no mapa
            ),
            child: Icon(MdiIcons.transmissionTower, color: Colors.white, size: 18),
          ),
        ),
      );
    }).toList();
  }

  List<Torre> get _filteredTowers {
    var towers = _allTowers;
    if (_selectedLinhaId != null) {
      towers = towers.where((t) => t.linhaId == _selectedLinhaId).toList();
    }
    return towers;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Inspeção'),
        leading: isWide ? null : Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_showLines ? Icons.show_chart_rounded : Icons.show_chart_outlined),
            onPressed: () => setState(() => _showLines = !_showLines),
            tooltip: 'Mostrar/Ocultar Linhas',
          ),
          IconButton(
            icon: Icon(_showPhotos ? Icons.photo_camera_rounded : Icons.photo_camera_outlined),
            onPressed: () => setState(() => _showPhotos = !_showPhotos),
            tooltip: 'Mostrar/Ocultar Fotos',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilterBar(),
                Expanded(
                  child: Stack(
                    children: [
                      _buildMap(),
                      if (_selectedTorre != null)
                        Positioned(
                          right: 16, top: 16, width: 320,
                          child: _buildTorreInfoCard(_selectedTorre!),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.bgSurface,
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _selectedLinhaId,
              decoration: const InputDecoration(
                labelText: 'Linha',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas as linhas')),
                ..._linhas.map((l) => DropdownMenuItem(value: l.id, child: Text(l.nome))),
              ],
              onChanged: (v) => setState(() {
                _selectedLinhaId = v;
                _selectedTorre = null;
                _recalculateLayers();
              }),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cell_tower, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Torres: ${_filteredTowers.length}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (_selectedLinhaId != null) ...[
                  Text(
                    ' / ${_allTowers.length} total',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final towers = _filteredTowers;

    final center = towers.isNotEmpty
        ? LatLng(
            towers.map((t) => t.latitude).reduce((a, b) => a + b) / towers.length,
            towers.map((t) => t.longitude).reduce((a, b) => a + b) / towers.length,
          )
        : const LatLng(-5.5, -42.5);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 6,
        onTap: (_, _) {
          if (_selectedTorre != null) {
            setState(() {
              _selectedTorre = null;
              _updateTowerMarkers(_filteredTowers);
            });
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
          userAgentPackageName: 'com.inspecao.torres',
          maxNativeZoom: 20,
        ),
        // Lines
        if (_showLines)
          PolylineLayer(polylines: _cachedPolylines),
        // Tower markers
        MarkerLayer(markers: _cachedTowerMarkers),
        // Photo markers
        if (_showPhotos)
          MarkerLayer(markers: _cachedPhotoMarkers),
      ],
    );
  }

  List<Polyline> _buildPolylines() {
    final polylines = <Polyline>[];
    // Group towers by linha
    final Map<String, List<Torre>> towersByLinha = {};
    for (final t in _allTowers) {
      if (t.linhaId != null) {
        towersByLinha.putIfAbsent(t.linhaId!, () => []).add(t);
      }
    }
    for (final towers in towersByLinha.values) {
      if (towers.length >= 2) {
        polylines.add(Polyline(
          points: towers.map((t) => LatLng(t.latitude, t.longitude)).toList(),
          strokeWidth: 3,
          color: AppColors.primaryLight.withValues(alpha: 0.7),
        ));
      }
    }
    return polylines;
  }

  List<Marker> _buildPhotoMarkers(List<Torre> filteredTowers) {
    final markers = <Marker>[];
    final towerIds = filteredTowers.map((t) => t.id).toSet();
    final photos = _allFotos.where((f) =>
        f.hasGps && (f.torreId == null || towerIds.contains(f.torreId))
    ).toList();

    for (final foto in photos) {
      markers.add(Marker(
        point: LatLng(foto.latitude!, foto.longitude!),
        width: 20, height: 20,
        child: GestureDetector(
          onTap: () => context.go('/fotos/${foto.id}'),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.8),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(Icons.camera_alt, color: Colors.white, size: 12),
          ),
        ),
      ));
    }
    return markers;
  }

  Widget _buildTorreInfoCard(Torre torre) {
    // Use cached data for fotos/anomalias count
    final fotosCount = _allFotos.where((f) => f.torreId == torre.id).length;

    return Card(
      color: AppColors.bgCard,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(MdiIcons.transmissionTower, color: AppColors.getCriticalityColor(torre.criticidadeAtual)),
                const SizedBox(width: 8),
                Expanded(child: Text(torre.codigoTorre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                CriticalityBadge(criticidade: torre.criticidadeAtual),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _selectedTorre = null),
                  child: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                ),
              ],
            ),
            if (torre.descricao != null) ...[
              const SizedBox(height: 8),
              Text(torre.descricao!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
            const Divider(height: 24),
            _infoRow('Tipo', torre.tipo ?? '—'),
            _infoRow('Coordenadas', '${torre.latitude.toStringAsFixed(4)}, ${torre.longitude.toStringAsFixed(4)}'),
            _infoRow('Fotos', '$fotosCount'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Ver Detalhes'),
                onPressed: () => context.go('/torres/${torre.id}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
