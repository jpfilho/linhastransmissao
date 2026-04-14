import 'dart:math';
import 'dart:typed_data';
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
import '../../torres/models/torre.dart';

class FotoDetailView extends StatefulWidget {
  final String fotoId;
  const FotoDetailView({super.key, required this.fotoId});

  @override
  State<FotoDetailView> createState() => _FotoDetailViewState();
}

class _FotoDetailViewState extends State<FotoDetailView> {
  dynamic _foto;
  Torre? _torre;
  AiAnalysis? _aiAnalysis;
  AiReport? _aiReport;
  bool _isAnalyzing = false;
  bool _isIdentifyingTower = false;
  bool _isMoondreamRunning = false;
  Uint8List? _annotatedImageBytes;
  Uint8List? _moondreamImageBytes;
  Map<String, dynamic>? _towerDetection;
  List<String> _allFotoIds = [];
  bool _isLoading = true;

  int get _currentIndex => _allFotoIds.indexOf(widget.fotoId);
  bool get _hasPrev => _currentIndex > 0;
  bool get _hasNext => _currentIndex >= 0 && _currentIndex < _allFotoIds.length - 1;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant FotoDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fotoId != widget.fotoId) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final foto = await SupabaseService.getFotoById(widget.fotoId);
    Torre? torre;
    AiAnalysis? aiAnalysis;
    AiReport? aiReport;
    try {
      aiAnalysis = await AiService.getAnalysis(widget.fotoId);
      aiReport = await AiService.getReport(widget.fotoId);
    } catch (_) {}
    if (foto?.torreId != null) {
      torre = await SupabaseService.getTorreById(foto!.torreId!);
    }
    final allFotos = await SupabaseService.getFotos();
    allFotos.sort((a, b) => a.nomeArquivo.compareTo(b.nomeArquivo));
    setState(() {
      _foto = foto;
      _torre = torre;
      _aiAnalysis = aiAnalysis;
      _aiReport = aiReport;
      _allFotoIds = allFotos.map((f) => f.id).toList();
      _isLoading = false;
    });
  }

  void _goToFoto(int index) {
    if (index >= 0 && index < _allFotoIds.length) {
      context.go('/fotos/${_allFotoIds[index]}');
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

    if (_foto == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Foto não encontrada')),
        body: const EmptyState(icon: Icons.error, title: 'Foto não encontrada'),
      );
    }

    final foto = _foto!;
    final posLabel = _currentIndex >= 0 ? '${_currentIndex + 1}/${_allFotoIds.length}' : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(foto.nomeArquivo),
        leading: isWide
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/fotos'))
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Foto anterior',
            onPressed: _hasPrev ? () => _goToFoto(_currentIndex - 1) : null,
          ),
          if (posLabel.isNotEmpty)
            Center(child: Text(posLabel, style: const TextStyle(color: AppColors.textMuted, fontSize: 13))),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Próxima foto',
            onPressed: _hasNext ? () => _goToFoto(_currentIndex + 1) : null,
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            icon: const Icon(Icons.rate_review_rounded),
            label: const Text('Avaliar'),
            onPressed: () => _showEvaluationDialog(context, foto.id),
          ),
          TextButton.icon(
            icon: const Icon(Icons.warning_rounded),
            label: const Text('Anomalia'),
            onPressed: () => context.go('/anomalias/nova'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _buildImageArea(foto)),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailsPanel(context, foto, _torre),
                      const SizedBox(height: 16),
                      _buildAiAnalysisCard(foto),
                    ],
                  )),
                ],
              )
            : Column(
                children: [
                  _buildImageArea(foto),
                  const SizedBox(height: 20),
                  _buildDetailsPanel(context, foto, _torre),
                  const SizedBox(height: 16),
                  _buildAiAnalysisCard(foto),
                ],
              ),
      ),
    );
  }

  Widget _buildImageArea(dynamic foto) {
    final storageUrl = SupabaseService.getPhotoUrl(foto.caminhoStorage);

    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 400,
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            onTap: () => FullScreenImageViewer.openFromStorage(context, foto.caminhoStorage, title: foto.nomeArquivo),
            child: Stack(
              fit: StackFit.expand,
              children: [
                foto.bytesData != null
                    ? Image.memory(foto.bytesData!, fit: BoxFit.contain, width: double.infinity, height: 400,
                        errorBuilder: (context, error, stackTrace) => _networkImage(storageUrl, foto.nomeArquivo))
                    : _networkImage(storageUrl, foto.nomeArquivo),
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fullscreen, color: Colors.white70, size: 16),
                        SizedBox(width: 4),
                        Text('Ampliar', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (foto.hasGps) ...[
          const SizedBox(height: 16),
          Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(initialCenter: LatLng(foto.latitude!, foto.longitude!), initialZoom: 15),
                  children: [
                    TileLayer(urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}', userAgentPackageName: 'com.inspecao.torres'),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(foto.latitude!, foto.longitude!), width: 32, height: 32,
                        child: Container(
                          decoration: BoxDecoration(color: AppColors.info, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                        ),
                      ),
                    ]),
                  ],
                ),
                MapFullscreenButton(
                  onTap: () => FullScreenMap.open(
                    context,
                    center: LatLng(foto.latitude!, foto.longitude!),
                    zoom: 17,
                    title: foto.nomeArquivo,
                    children: [
                      MarkerLayer(markers: [
                        Marker(
                          point: LatLng(foto.latitude!, foto.longitude!), width: 32, height: 32,
                          child: Container(
                            decoration: BoxDecoration(color: AppColors.info, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _networkImage(String url, String fileName) {
    return Image.network(
      url,
      fit: BoxFit.contain,
      width: double.infinity,
      height: 400,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
              ),
              const SizedBox(height: 12),
              Text('Carregando $fileName...', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => _imagePlaceholder(fileName),
    );
  }

  Widget _imagePlaceholder(String fileName) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.image, size: 80, color: AppColors.textMuted),
        const SizedBox(height: 12),
        Text(fileName, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        const Text('Imagem não disponível no Storage', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _buildDetailsPanel(BuildContext context, dynamic foto, dynamic torre) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: StatusBadge(status: foto.statusAvaliacao, labels: AppConstants.statusAvaliacaoLabels)),
            const SizedBox(width: 8),
            Expanded(child: StatusBadge(status: foto.statusAssociacao, labels: AppConstants.statusAssociacaoLabels)),
          ],
        ),
        const SizedBox(height: 16),
        _buildSection('Metadados', [
          _row('Arquivo', foto.nomeArquivo),
          _row('Campanha', foto.campanhaNome ?? '—'),
          _row('Linha', foto.linhaNome ?? '—'),
          _row('Data/Hora', foto.dataHoraCaptura?.toString().substring(0, 19) ?? '—'),
          _row('Qualidade', '${(foto.qualidadeImagem * 100).toStringAsFixed(0)}%'),
        ]),
        const SizedBox(height: 16),
        _buildSection('Geolocalização', [
          _row('Latitude', foto.latitude?.toStringAsFixed(6) ?? 'N/A'),
          _row('Longitude', foto.longitude?.toStringAsFixed(6) ?? 'N/A'),
          _row('Altitude', foto.altitude != null ? '${foto.altitude.toStringAsFixed(0)} m' : '—'),
          _row('Azimute', foto.azimute != null ? '${foto.azimute.toStringAsFixed(1)}°' : '—'),
        ]),
        const SizedBox(height: 16),
        _buildSection('Associação', [
          _row('Torre', torre?.codigoTorre ?? 'Não associada'),
          _row('Distância', foto.distanciaTorreM != null ? '${foto.distanciaTorreM.toStringAsFixed(1)} m' : '—'),
          _row('Status', AppConstants.statusAssociacaoLabels[foto.statusAssociacao] ?? foto.statusAssociacao),
        ]),
        if (torre != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: Icon(MdiIcons.transmissionTower, size: 16),
              label: Text('Ver Torre ${torre.codigoTorre}'),
              onPressed: () => context.go('/torres/${torre.id}'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.link, size: 16),
            label: const Text('Corrigir Associação'),
            onPressed: () => _showAssociationDialog(context),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  void _showEvaluationDialog(BuildContext context, String fotoId) {
    bool? imagemUtil;
    String? categoria;
    String? qualidade;
    bool inspecaoComplementar = false;
    final obsController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Avaliar Foto'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Imagem útil?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      ChoiceChip(label: const Text('Sim'), selected: imagemUtil == true, onSelected: (v) => setDialogState(() => imagemUtil = v ? true : null)),
                      const SizedBox(width: 8),
                      ChoiceChip(label: const Text('Não'), selected: imagemUtil == false, onSelected: (v) => setDialogState(() => imagemUtil = v ? false : null)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Categoria', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: AppConstants.categoriasFoto.map((c) => ChoiceChip(
                      label: Text(AppConstants.categoriaLabels[c] ?? c),
                      selected: categoria == c,
                      onSelected: (v) => setDialogState(() => categoria = v ? c : null),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Qualidade', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Row(
                    children: ['ruim', 'media', 'boa'].map((q) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(q == 'ruim' ? 'Ruim' : q == 'media' ? 'Média' : 'Boa'),
                        selected: qualidade == q,
                        onSelected: (v) => setDialogState(() => qualidade = v ? q : null),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(controller: obsController, decoration: const InputDecoration(labelText: 'Observações técnicas'), maxLines: 3),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: inspecaoComplementar,
                    title: const Text('Necessita inspeção complementar', style: TextStyle(fontSize: 13)),
                    onChanged: (v) => setDialogState(() => inspecaoComplementar = v ?? false),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Avaliação salva com sucesso!'), backgroundColor: AppColors.success),
                );
              },
              child: const Text('Salvar Avaliação'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAssociationDialog(BuildContext context) {
    final foto = _foto!;
    final hasGps = foto.hasGps == true && foto.latitude != null && foto.longitude != null;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Corrigir Associação', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                      IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                ),
                // Body
                Expanded(
                  child: FutureBuilder<List<Torre>>(
                    future: SupabaseService.getTorres(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final allTorres = snapshot.data!;

                      // Sort by distance from photo if GPS available
                      List<_TorreDistance> torresWithDistance;
                      if (hasGps) {
                        torresWithDistance = allTorres.map((t) {
                          final dist = _haversineDistance(
                            foto.latitude!, foto.longitude!,
                            t.latitude, t.longitude,
                          );
                          return _TorreDistance(torre: t, distanceM: dist);
                        }).toList()
                          ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
                      } else {
                        torresWithDistance = allTorres.map((t) => _TorreDistance(torre: t, distanceM: -1)).toList();
                      }

                      // Take nearest 50 for the map
                      final nearestForMap = hasGps ? torresWithDistance.take(50).toList() : <_TorreDistance>[];

                      return Column(
                        children: [
                          // Map showing photo + nearby towers
                          if (hasGps)
                            SizedBox(
                              height: 280,
                              child: FlutterMap(
                                options: MapOptions(
                                  initialCenter: LatLng(foto.latitude!, foto.longitude!),
                                  initialZoom: 14,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
                                    userAgentPackageName: 'com.inspecao.torres',
                                  ),
                                  // Tower markers
                                  MarkerLayer(
                                    markers: [
                                      // Photo marker (blue, larger)
                                      Marker(
                                        point: LatLng(foto.latitude!, foto.longitude!),
                                        width: 36, height: 36,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: AppColors.info,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 3),
                                            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                                          ),
                                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                                        ),
                                      ),
                                      // Nearby tower markers
                                      ...nearestForMap.map((td) => Marker(
                                        point: LatLng(td.torre.latitude, td.torre.longitude),
                                        width: 32, height: 32,
                                        child: GestureDetector(
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            _associateTorre(td.torre);
                                          },
                                          child: Tooltip(
                                            message: '${td.torre.codigoTorre} — ${td.distanceM.toStringAsFixed(0)}m',
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: AppColors.getColorForLinha(td.torre.linhaNome ?? td.torre.linhaId),
                                                shape: BoxShape.circle,
                                                border: Border.all(color: Colors.white, width: 2),
                                              ),
                                              child: Icon(MdiIcons.transmissionTower, color: Colors.white, size: 14),
                                            ),
                                          ),
                                        ),
                                      )),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          // Divider with info
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: AppColors.bgSurface,
                            child: Row(
                              children: [
                                Icon(MdiIcons.transmissionTower, size: 14, color: AppColors.textMuted),
                                const SizedBox(width: 6),
                                Text(
                                  hasGps
                                      ? 'Torres mais próximas (${torresWithDistance.length})'
                                      : 'Selecione uma torre (${allTorres.length})',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                                ),
                                if (hasGps) ...[
                                  const Spacer(),
                                  const Icon(Icons.camera_alt, size: 12, color: AppColors.info),
                                  const SizedBox(width: 4),
                                  const Text('= Foto', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                ],
                              ],
                            ),
                          ),
                          // Tower list sorted by distance
                          Expanded(
                            child: ListView.builder(
                              itemCount: torresWithDistance.length,
                              itemBuilder: (context, index) {
                                final td = torresWithDistance[index];
                                final t = td.torre;
                                final isCurrentAssoc = t.id == foto.torreId;
                                return ListTile(
                                  dense: true,
                                  selected: isCurrentAssoc,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: AppColors.getColorForLinha(t.linhaNome ?? t.linhaId),
                                    child: Icon(MdiIcons.transmissionTower, color: Colors.white, size: 14),
                                  ),
                                  title: Row(
                                    children: [
                                      Text(t.codigoTorre, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                      if (isCurrentAssoc) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                          child: const Text('Atual', style: TextStyle(fontSize: 10, color: AppColors.success)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    td.distanceM >= 0
                                        ? '${td.distanceM.toStringAsFixed(0)}m — ${t.linhaNome ?? t.descricao ?? ''}'
                                        : t.linhaNome ?? t.descricao ?? '',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: td.distanceM >= 0
                                      ? Text('${td.distanceM.toStringAsFixed(0)}m', style: TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.w600,
                                          color: td.distanceM < 200 ? AppColors.success : td.distanceM < 500 ? AppColors.warning : AppColors.textMuted,
                                        ))
                                      : null,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _associateTorre(t);
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _associateTorre(Torre torre) async {
    try {
      await SupabaseService.updateFotoAssociation(
        fotoId: _foto!.id,
        torreId: torre.id,
        linhaId: torre.linhaId,
        torreCodigo: torre.codigoTorre,
        linhaNome: torre.linhaNome,
        distanciaM: _foto!.hasGps == true
            ? _haversineDistance(_foto!.latitude!, _foto!.longitude!, torre.latitude, torre.longitude)
            : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Foto associada à torre ${torre.codigoTorre}'), backgroundColor: AppColors.success),
        );
        _loadData(); // Reload to show updated association
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao associar: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// Haversine distance in meters between two lat/lng points
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ═══════════════════════════════════════════════════════
  // AI ANALYSIS CARD
  // ═══════════════════════════════════════════════════════

  Widget _buildAiAnalysisCard(dynamic foto) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Análise IA', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_aiAnalysis != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _severityColor(_aiAnalysis!.severityScore).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _aiAnalysis!.severityLabel,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _severityColor(_aiAnalysis!.severityScore)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_aiAnalysis == null && !_isAnalyzing) ...[
            const Text('Nenhuma análise de IA disponível.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Analisar com IA'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () => _triggerAiAnalysis(foto),
              ),
            ),
          ],

          if (_isAnalyzing) ...[
            const Center(
              child: Column(
                children: [
                  SizedBox(height: 8),
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Analisando imagem com IA...', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  SizedBox(height: 8),
                ],
              ),
            ),
          ],

          if (_aiAnalysis != null) ...[
            // Severity gauge
            _buildGauge('Severidade', _aiAnalysis!.severityScore, _severityColor(_aiAnalysis!.severityScore)),
            const SizedBox(height: 8),
            _buildGauge('Confiança', _aiAnalysis!.confidence * 100, AppColors.info),
            const SizedBox(height: 12),

            // Tags
            if (_aiAnalysis!.detectedTags.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _aiAnalysis!.detectedTags.map((tag) {
                  final color = tag.contains('Fogo') ? AppColors.error
                      : tag.contains('Vegetação') ? Colors.green
                      : tag.contains('Estrutural') ? Colors.orange
                      : AppColors.warning;
                  return Chip(
                    label: Text(tag, style: TextStyle(fontSize: 11, color: color)),
                    backgroundColor: color.withValues(alpha: 0.1),
                    side: BorderSide(color: color.withValues(alpha: 0.3)),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            // Quality metrics
            Row(
              children: [
                Expanded(child: _buildMiniStat('Nitidez', '${_aiAnalysis!.qualityBlur.toStringAsFixed(0)}%', Icons.blur_on)),
                const SizedBox(width: 8),
                Expanded(child: _buildMiniStat('Exposição', '${_aiAnalysis!.qualityExposure.toStringAsFixed(0)}%', Icons.wb_sunny)),
              ],
            ),

            // Summary
            if (_aiAnalysis!.summary != null && _aiAnalysis!.summary!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_aiAnalysis!.summary!, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
              ),
            ],

            // AI Report
            if (_aiReport != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              const Text('Relatório IA', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(_aiReport!.content, style: const TextStyle(fontSize: 12)),
              if (_aiReport!.suggestedAction != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.tips_and_updates, size: 14, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_aiReport!.suggestedAction!, style: const TextStyle(fontSize: 12, color: AppColors.warning))),
                  ],
                ),
              ],
            ],

            // Re-analyze button
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Re-analisar', style: TextStyle(fontSize: 12)),
                    onPressed: () => _triggerAiAnalysis(foto),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.description, size: 16),
                    label: const Text('Gerar Relatório', style: TextStyle(fontSize: 12)),
                    onPressed: () => _triggerAiSummary(foto),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _isIdentifyingTower
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(MdiIcons.transmissionTower, size: 18),
                label: Text(_isIdentifyingTower ? 'Identificando...' : 'Identificar Torre na Foto'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                ),
                onPressed: _isIdentifyingTower ? null : () => _triggerTowerIdentification(foto),
              ),
            ),
            // Moondream mapping button — only shown when photo has a tower
            if (_torre != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _isMoondreamRunning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.layers, size: 18),
                  label: Text(_isMoondreamRunning ? 'Mapeando...' : 'Mapear Veg. com Moondream 3'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isMoondreamRunning ? null : () => _triggerMoondreamAnnotation(foto),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildGauge(String label, double value, Color color) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value / 100,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 40, child: Text('${value.toStringAsFixed(0)}%', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Color _severityColor(double score) {
    if (score >= 75) return AppColors.error;
    if (score >= 50) return Colors.orange;
    if (score >= 20) return AppColors.warning;
    return AppColors.success;
  }

  Future<void> _triggerAiAnalysis(dynamic foto) async {
    setState(() => _isAnalyzing = true);
    try {
      final imageUrl = SupabaseService.getPhotoUrl(foto.caminhoStorage);
      final analysis = await AiService.analyzeImage(foto.id, imageUrl);
      setState(() {
        _aiAnalysis = analysis;
        _isAnalyzing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(analysis != null ? '✅ Análise IA concluída!' : '⚠️ Serviço IA indisponível'),
          backgroundColor: analysis != null ? AppColors.success : AppColors.error,
        ));
      }
    } catch (e) {
      setState(() => _isAnalyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Erro na análise: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _triggerTowerIdentification(dynamic foto) async {
    setState(() => _isIdentifyingTower = true);
    try {
      final imageUrl = SupabaseService.getPhotoUrl(foto.caminhoStorage);
      final result = await AiService.annotateImage(foto.id, imageUrl);
      if (result != null && mounted) {
        setState(() {
          _annotatedImageBytes = result['imageBytes'] as Uint8List;
          _towerDetection = result['detection'] as Map<String, dynamic>?;
          _isIdentifyingTower = false;
        });
        _showAnnotatedImageDialog(
          result['towerCode'] as String? ?? 'Desconhecida',
          result['towerFunction'] as String? ?? 'desconhecido',
          result['towerStructure'] as String? ?? 'desconhecido',
          result['towerHeight'] as String? ?? '0',
        );
      } else {
        setState(() => _isIdentifyingTower = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('⚠️ Não foi possível identificar a torre.'),
            backgroundColor: AppColors.error,
          ));
        }
      }
    } catch (e) {
      setState(() => _isIdentifyingTower = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Erro: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  void _showAnnotatedImageDialog(String towerCode, String towerFunction, String towerStructure, String heightM) {
    final functionLabels = {
      'ancoragem': 'Ancoragem',
      'suspensao': 'Suspensão',
      'transposicao': 'Transposição',
      'derivacao': 'Derivação',
      'terminal': 'Terminal',
      'desconhecido': 'Não identificado',
    };
    final structureLabels = {
      'trelica_autoportante': 'Treliça Autoportante',
      'trelica_estaiada': 'Treliça Estaiada',
      'monopolo': 'Monopolo',
      'concreto': 'Concreto',
      'madeira': 'Madeira',
      'desconhecido': 'Não identificado',
    };
    final functionLabel = functionLabels[towerFunction] ?? towerFunction;
    final structureLabel = structureLabels[towerStructure] ?? towerStructure;
    
    // Extract extra info from detection
    final towerIdInfo = _towerDetection?['tower_identification'] as Map<String, dynamic>?;
    final circuitType = towerIdInfo?['circuit_type'] ?? '—';
    final insulators = towerIdInfo?['insulators_type'] ?? '—';
    final plaqueText = towerIdInfo?['plaque_text'];
    final heightDisplay = (heightM != '0' && heightM != 'null') ? '~${heightM}m' : '—';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 750),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFF2196F3),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Icon(MdiIcons.transmissionTower, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Torre: $towerCode',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('Função: $functionLabel  •  $structureLabel',
                            style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              // Image
              if (_annotatedImageBytes != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_annotatedImageBytes!, fit: BoxFit.contain),
                    ),
                  ),
                ),
              // Info cards
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _infoChip(Icons.category, 'Função', functionLabel),
                    const SizedBox(width: 8),
                    _infoChip(Icons.height, 'Altura', heightDisplay),
                    const SizedBox(width: 8),
                    _infoChip(Icons.electrical_services, 'Circuito', circuitType),
                    const SizedBox(width: 8),
                    _infoChip(Icons.lens_outlined, 'Isoladores', insulators),
                  ],
                ),
              ),
              if (plaqueText != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.badge, size: 16, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text('Placa: $plaqueText', style: const TextStyle(color: Colors.amber, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: Colors.white54),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerMoondreamAnnotation(dynamic foto) async {
    if (_torre == null) return;
    setState(() => _isMoondreamRunning = true);
    try {
      // Fetch suppression mapping for this tower using actual columns
      final supressao = await SupabaseService.client
          .from('mapeamento_supressao')
          .select('vao_frente_m, largura_m, map_mec_extensao, map_man_extensao, descricao_servico')
          .eq('torre_id', _torre!.id)
          .maybeSingle();

      List<Map<String, dynamic>> segments = [];
      double vaoM = 100.0;
      double larguraM = 40.0;

      if (supressao != null) {
        vaoM = (supressao['vao_frente_m'] as num?)?.toDouble() ?? 100.0;
        larguraM = (supressao['largura_m'] as num?)?.toDouble() ?? 40.0;
        final mecExt = (supressao['map_mec_extensao'] as num?)?.toDouble() ?? 0.0;
        final manExt = (supressao['map_man_extensao'] as num?)?.toDouble() ?? 0.0;

        double cursor = 0;
        if (mecExt > 0) {
          segments.add({'tipo': 'mecanizado', 'inicio': cursor.toInt(), 'fim': (cursor + mecExt).toInt()});
          cursor += mecExt;
        }
        if (manExt > 0) {
          segments.add({'tipo': 'manual', 'inicio': cursor.toInt(), 'fim': (cursor + manExt).toInt()});
          cursor += manExt;
        }
        if (cursor < vaoM && vaoM > 0) {
          segments.add({'tipo': 'manual', 'inicio': cursor.toInt(), 'fim': vaoM.toInt()});
        }
        if (segments.isEmpty && vaoM > 0) {
          segments.add({'tipo': 'manual', 'inicio': 0, 'fim': vaoM.toInt()});
        }
      }

      if (segments.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('⚠️ Nenhum segmento de mapeamento encontrado para esta torre.'),
            backgroundColor: AppColors.warning,
          ));
        }
        setState(() => _isMoondreamRunning = false);
        return;
      }

      final imageUrl = SupabaseService.getPhotoUrl(foto.caminhoStorage);
      final bytes = await AiService.annotateMoondream(
        imageUrl: imageUrl,
        segments: segments,
        vaoTotalM: vaoM,
        larguraM: larguraM,
        fotoId: foto.id,
        torreCodigo: _torre!.codigoTorre,
      );

      if (bytes != null && mounted) {
        setState(() {
          _moondreamImageBytes = bytes;
          _isMoondreamRunning = false;
        });
        _showMoondreamDialog(segments, vaoM);
      } else {
        setState(() => _isMoondreamRunning = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('⚠️ Serviço Moondream indisponível.'),
            backgroundColor: AppColors.error,
          ));
        }
      }
    } catch (e) {
      setState(() => _isMoondreamRunning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Erro Moondream: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  void _showMoondreamDialog(List<Map<String, dynamic>> segments, double vaoM) {
    final colorMap = {
      'mecanizado': Colors.purple,
      'manual':     Colors.orange,
      'seletivo':   Colors.green,
      'cultivado':  Colors.lightGreen,
      'nao_rocar':  Colors.grey,
    };
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 750, maxHeight: 800),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF2D6A4F),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.layers, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Mapeamento de Vegetação — Moondream 3',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('Vão total: ${vaoM.toStringAsFixed(0)}m  •  ${segments.length} segmento(s)',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              // Annotated image
              if (_moondreamImageBytes != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_moondreamImageBytes!, fit: BoxFit.contain),
                    ),
                  ),
                ),
              // Legend chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Wrap(
                  spacing: 8, runSpacing: 6,
                  children: segments.map((seg) {
                    final tipo = seg['tipo'] as String? ?? 'manual';
                    final inicio = seg['inicio'] as num? ?? 0;
                    final fim = seg['fim'] as num? ?? vaoM;
                    final color = colorMap[tipo] ?? Colors.grey;
                    return Chip(
                      avatar: CircleAvatar(backgroundColor: color, radius: 8),
                      label: Text(
                        '${tipo[0].toUpperCase()}${tipo.substring(1)}: ${inicio.toInt()}–${fim.toInt()}m',
                        style: const TextStyle(fontSize: 11),
                      ),
                      backgroundColor: color.withValues(alpha: 0.15),
                      side: BorderSide(color: color.withValues(alpha: 0.4)),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _triggerAiSummary(dynamic foto) async {
    setState(() => _isAnalyzing = true);
    try {
      final imageUrl = SupabaseService.getPhotoUrl(foto.caminhoStorage);
      final report = await AiService.generateSummary(foto.id, imageUrl: imageUrl);
      if (report != null) {
        setState(() {
          _aiReport = report;
          _isAnalyzing = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Relatório IA gerado com sucesso!'),
            backgroundColor: AppColors.success,
          ));
        }
      } else {
        setState(() => _isAnalyzing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('⚠️ Serviço IA indisponível. Verifique se o serviço está rodando na porta 8000.'),
            backgroundColor: AppColors.error,
          ));
        }
      }
    } catch (e) {
      setState(() => _isAnalyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Erro ao gerar relatório: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }
}

class _TorreDistance {
  final Torre torre;
  final double distanceM;
  const _TorreDistance({required this.torre, required this.distanceM});
}
