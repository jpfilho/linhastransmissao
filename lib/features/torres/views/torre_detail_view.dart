import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/config/app_constants.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/services/ai_service.dart';
import '../../../shared/models/ai_models.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../../shared/widgets/image_viewer.dart';
import '../../../shared/widgets/fullscreen_map.dart';
import '../models/torre.dart';
import '../../fotos/models/foto.dart';
import '../../anomalias/models/anomalia.dart';

class TorreDetailView extends StatefulWidget {
  final String torreId;
  const TorreDetailView({super.key, required this.torreId});

  @override
  State<TorreDetailView> createState() => _TorreDetailViewState();
}

class _TorreDetailViewState extends State<TorreDetailView> {
  Torre? _torre;
  List<Foto> _fotos = [];
  List<Anomalia> _anomalias = [];
  TowerRisk? _towerRisk;
  List<String> _allTorreIds = [];
  bool _isLoading = true;

  int get _currentIndex => _allTorreIds.indexOf(widget.torreId);
  bool get _hasPrev => _currentIndex > 0;
  bool get _hasNext => _currentIndex >= 0 && _currentIndex < _allTorreIds.length - 1;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant TorreDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.torreId != widget.torreId) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      SupabaseService.getTorreById(widget.torreId),
      SupabaseService.getFotosByTorre(widget.torreId),
      SupabaseService.getAnomalias(torreId: widget.torreId),
      SupabaseService.getTorres(),
    ]);
    final allTorres = results[3] as List<Torre>;
    final torre = results[0] as Torre?;
    // Filter to same line and sort by natural numeric order for sequential navigation
    final sameLine = torre?.linhaId != null
        ? allTorres.where((t) => t.linhaId == torre!.linhaId).toList()
        : allTorres;
    sameLine.sort((a, b) => _naturalCompare(a.codigoTorre, b.codigoTorre));
    setState(() {
      _torre = torre;
      _fotos = results[1] as List<Foto>;
      _anomalias = results[2] as List<Anomalia>;
      _allTorreIds = sameLine.map((t) => t.id).toList();
      _isLoading = false;
    });
    // Load AI data async (non-blocking)
    AiService.getTowerRisk(widget.torreId).then((risk) {
      if (mounted) setState(() => _towerRisk = risk);
    }).catchError((_) {});
  }

  int _naturalCompare(String a, String b) {
    final regExp = RegExp(r'(\d+)|(\D+)');
    final partsA = regExp.allMatches(a).toList();
    final partsB = regExp.allMatches(b).toList();
    for (int i = 0; i < partsA.length && i < partsB.length; i++) {
      final pa = partsA[i].group(0)!;
      final pb = partsB[i].group(0)!;
      final na = int.tryParse(pa);
      final nb = int.tryParse(pb);
      int cmp = (na != null && nb != null) ? na.compareTo(nb) : pa.compareTo(pb);
      if (cmp != 0) return cmp;
    }
    return partsA.length.compareTo(partsB.length);
  }

  void _goToTorre(int index) {
    if (index >= 0 && index < _allTorreIds.length) {
      context.go('/torres/${_allTorreIds[index]}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Carregando...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_torre == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Torre não encontrada')),
        body: const EmptyState(icon: Icons.error, title: 'Torre não encontrada'),
      );
    }

    final torre = _torre!;
    final posLabel = _currentIndex >= 0 ? '${_currentIndex + 1}/${_allTorreIds.length}' : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(torre.codigoTorre),
        leading: isWide
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/torres'))
            : null,
        actions: [
          if (posLabel.isNotEmpty)
            Center(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(posLabel, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            )),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Torre anterior',
            onPressed: _hasPrev ? () => _goToTorre(_currentIndex - 1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Próxima torre',
            onPressed: _hasNext ? () => _goToTorre(_currentIndex + 1) : null,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.getCriticalityColor(torre.criticidadeAtual).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(MdiIcons.transmissionTower, color: AppColors.getCriticalityColor(torre.criticidadeAtual), size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(torre.codigoTorre, style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(width: 12),
                          CriticalityBadge(criticidade: torre.criticidadeAtual),
                        ],
                      ),
                      if (torre.descricao != null)
                        Text(torre.descricao!, style: TextStyle(color: AppColors.textSecondary)),
                      if (torre.linhaNome != null)
                        Text(torre.linhaNome!, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Info & Map row
            if (isWide) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildInfoCard(torre)),
                  const SizedBox(width: 20),
                  Expanded(child: _buildMiniMap(torre)),
                ],
              ),
            ] else ...[
              _buildInfoCard(torre),
              const SizedBox(height: 20),
              _buildMiniMap(torre),
            ],

            const SizedBox(height: 24),

            // Stats
            Row(
              children: [
                Expanded(child: StatsCard(title: 'Fotos', value: '${_fotos.length}', icon: Icons.photo_camera_rounded, color: AppColors.info)),
                const SizedBox(width: 12),
                Expanded(child: StatsCard(
                  title: 'Anomalias', value: '${_anomalias.length}', icon: Icons.warning_rounded,
                  color: _anomalias.isNotEmpty ? AppColors.warning : AppColors.textMuted,
                )),
                const SizedBox(width: 12),
                Expanded(child: StatsCard(
                  title: 'Avaliadas', value: '${_fotos.where((f) => f.statusAvaliacao == 'avaliada').length}/${_fotos.length}',
                  icon: Icons.check_circle_rounded, color: AppColors.success,
                )),
              ],
            ),

            // AI Risk Section
            if (_towerRisk != null) ...[
              const SizedBox(height: 16),
              _buildRiskCard(_towerRisk!),
            ],

            // Photos gallery
            const SizedBox(height: 24),
            SectionHeader(
              title: 'Galeria de Fotos',
              trailing: TextButton(
                onPressed: () => context.go('/fotos'),
                child: const Text('Ver todas'),
              ),
            ),
            const SizedBox(height: 8),
            _fotos.isEmpty
                ? const EmptyState(icon: Icons.photo_library, title: 'Nenhuma foto associada')
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isWide ? 4 : 2,
                      childAspectRatio: 1.0,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _fotos.length,
                    itemBuilder: (context, index) {
                      final foto = _fotos[index];
                      return InkWell(
                        onTap: () => context.go('/fotos/${foto.id}'),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.bgElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              StorageThumbnail(
                                storagePath: foto.caminhoStorage,
                                width: double.infinity,
                                height: double.infinity,
                                borderRadius: BorderRadius.circular(10),
                                fit: BoxFit.cover,
                              ),
                              // Gradient overlay at bottom
                              Positioned(
                                bottom: 0, left: 0, right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Colors.transparent, Colors.black87],
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        foto.nomeArquivo,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white),
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          StatusBadge(status: foto.statusAvaliacao, labels: AppConstants.statusAvaliacaoLabels),
                                          const SizedBox(width: 4),
                                          Text('${foto.distanciaTorreM?.toStringAsFixed(0) ?? '?'}m', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Fullscreen button
                              Positioned(
                                top: 4, right: 4,
                                child: IconButton(
                                  icon: const Icon(Icons.fullscreen, color: Colors.white70, size: 20),
                                  style: IconButton.styleFrom(backgroundColor: Colors.black38, padding: const EdgeInsets.all(4), minimumSize: const Size(28, 28)),
                                  onPressed: () => FullScreenImageViewer.openGallery(
                                    context,
                                    _fotos.map((f) => f.caminhoStorage).toList(),
                                    initialIndex: index,
                                    titles: _fotos.map((f) => f.nomeArquivo).toList(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

            // Anomalies
            if (_anomalias.isNotEmpty) ...[
              const SizedBox(height: 24),
              SectionHeader(title: 'Anomalias Registradas'),
              const SizedBox(height: 8),
              ..._anomalias.map((a) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(Icons.warning, color: AppColors.getCriticalityColor(a.severidade)),
                  title: Text(AppConstants.anomaliaLabels[a.tipo] ?? a.tipo),
                  subtitle: Text(a.descricao ?? '', style: const TextStyle(fontSize: 12)),
                  trailing: CriticalityBadge(criticidade: a.severidade, compact: true),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(Torre torre) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Informações', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _row('Código', torre.codigoTorre),
          _row('Tipo', torre.tipo ?? '—'),
          _row('Latitude', torre.latitude.toStringAsFixed(6)),
          _row('Longitude', torre.longitude.toStringAsFixed(6)),
          _row('Altitude', torre.altitude != null ? '${torre.altitude!.toStringAsFixed(0)} m' : '—'),
          _row('Criticidade', AppConstants.severidadeLabels[torre.criticidadeAtual] ?? torre.criticidadeAtual),
        ],
      ),
    );
  }

  Widget _buildMiniMap(Torre torre) {
    final mapChildren = [
      MarkerLayer(
        markers: [
          Marker(
            point: LatLng(torre.latitude, torre.longitude),
            width: 40,
            height: 40,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.getCriticalityColor(torre.criticidadeAtual),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: Icon(MdiIcons.transmissionTower, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    ];

    return Container(
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(torre.latitude, torre.longitude),
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
                userAgentPackageName: 'com.inspecao.torres',
              ),
              ...mapChildren,
            ],
          ),
          MapFullscreenButton(
            onTap: () => FullScreenMap.open(
              context,
              center: LatLng(torre.latitude, torre.longitude),
              zoom: 16,
              title: torre.codigoTorre,
              children: mapChildren,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildRiskCard(TowerRisk risk) {
    final riskColor = risk.riskScore >= 75 ? AppColors.error
        : risk.riskScore >= 50 ? Colors.orange
        : risk.riskScore >= 25 ? AppColors.warning
        : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: riskColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield, size: 20, color: riskColor),
              const SizedBox(width: 8),
              const Text('Risco IA', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(risk.priorityLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: riskColor)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Risk score gauge
          Row(
            children: [
              Text('${risk.riskScore.toStringAsFixed(0)}', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: riskColor)),
              const SizedBox(width: 8),
              Text('/100', style: TextStyle(fontSize: 16, color: AppColors.textMuted)),
              const SizedBox(width: 16),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: risk.riskScore / 100,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation(riskColor),
                    minHeight: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Trend
          Row(
            children: [
              Icon(
                risk.trend == 'improving' ? Icons.trending_up : risk.trend == 'worsening' ? Icons.trending_down : Icons.trending_flat,
                size: 16,
                color: risk.trend == 'improving' ? AppColors.success : risk.trend == 'worsening' ? AppColors.error : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(risk.trendLabel, style: const TextStyle(fontSize: 12)),
              const Spacer(),
              if (risk.daysSinceInspection != null)
                Text('Última inspeção: ${risk.daysSinceInspection} dias', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 12),

          // Risk breakdown
          _riskRow('Vegetação', risk.vegetationRisk, Colors.green),
          _riskRow('Incêndio', risk.fireRisk, Colors.deepOrange),
          _riskRow('Raios', risk.lightningRisk, Colors.amber),
        ],
      ),
    );
  }

  Widget _riskRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: value / 100, backgroundColor: AppColors.border, valueColor: AlwaysStoppedAnimation(color), minHeight: 6),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(width: 30, child: Text('${value.toStringAsFixed(0)}', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
