import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../../shared/widgets/image_viewer.dart';
import '../../../shared/models/linha.dart';
import '../../../shared/models/campanha.dart';
import '../../torres/models/torre.dart';
import '../../fotos/models/foto.dart';

class TemporalComparisonView extends StatefulWidget {
  const TemporalComparisonView({super.key});

  @override
  State<TemporalComparisonView> createState() => _TemporalComparisonViewState();
}

class _TemporalComparisonViewState extends State<TemporalComparisonView> {
  // Selection state
  String? _selectedLinhaId;
  String? _selectedTorreId;
  String? _campanha1Id;
  String? _campanha2Id;
  String _evolution = 'sem_alteracao';

  // Data
  List<Linha> _linhas = [];
  List<Torre> _torresForLinha = [];
  List<Campanha> _campanhas = [];
  Torre? _selectedTorre;
  List<Foto> _fotos1 = [];
  List<Foto> _fotos2 = [];
  bool _isLoading = true;
  bool _isLoadingTorres = false;
  bool _isLoadingFotos = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      SupabaseService.getLinhas(),
      SupabaseService.getCampanhas(),
    ]);
    setState(() {
      _linhas = results[0] as List<Linha>;
      _campanhas = results[1] as List<Campanha>;
      _isLoading = false;
    });
  }

  Future<void> _loadTorresForLinha(String linhaId) async {
    setState(() => _isLoadingTorres = true);
    final torres = await SupabaseService.getTorres(linhaId: linhaId);
    // Natural sort
    torres.sort((a, b) => _naturalCompare(a.codigoTorre, b.codigoTorre));
    setState(() {
      _torresForLinha = torres;
      _isLoadingTorres = false;
    });
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

  Future<void> _loadFotos() async {
    if (_selectedTorreId == null) return;
    setState(() => _isLoadingFotos = true);

    final futures = <Future<List<Foto>>>[];
    if (_campanha1Id != null) {
      futures.add(SupabaseService.getFotos(campanhaId: _campanha1Id, torreId: _selectedTorreId));
    } else {
      futures.add(Future.value(<Foto>[]));
    }
    if (_campanha2Id != null) {
      futures.add(SupabaseService.getFotos(campanhaId: _campanha2Id, torreId: _selectedTorreId));
    } else {
      futures.add(Future.value(<Foto>[]));
    }

    final results = await Future.wait(futures);
    setState(() {
      _fotos1 = results[0];
      _fotos2 = results[1];
      _isLoadingFotos = false;
    });
  }

  void _onLinhaChanged(String? linhaId) {
    setState(() {
      _selectedLinhaId = linhaId;
      _selectedTorreId = null;
      _selectedTorre = null;
      _torresForLinha = [];
      _fotos1 = [];
      _fotos2 = [];
    });
    if (linhaId != null) _loadTorresForLinha(linhaId);
  }

  // Store earliest photo date per campaign (for display and sorting)
  Map<String, DateTime?> _campaignPhotoDates = {};

  void _onTorreChanged(String? torreId) async {
    setState(() {
      _selectedTorreId = torreId;
      _selectedTorre = torreId != null ? _torresForLinha.firstWhere((t) => t.id == torreId) : null;
      _campanha1Id = null;
      _campanha2Id = null;
      _fotos1 = [];
      _fotos2 = [];
      _campaignPhotoDates = {};
    });

    if (torreId == null) return;

    // Auto-detect campaigns that have photos for this tower
    // and get the earliest photo date per campaign
    setState(() => _isLoadingFotos = true);
    try {
      final photoDates = <String, DateTime?>{};
      final campanhasComFotos = <String>[];

      for (final c in _campanhas) {
        final fotos = await SupabaseService.getFotos(campanhaId: c.id, torreId: torreId);
        if (fotos.isNotEmpty) {
          campanhasComFotos.add(c.id);
          // Find earliest photo capture date from EXIF metadata
          DateTime? earliest;
          for (final f in fotos) {
            if (f.dataHoraCaptura != null) {
              if (earliest == null || f.dataHoraCaptura!.isBefore(earliest)) {
                earliest = f.dataHoraCaptura;
              }
            }
          }
          photoDates[c.id] = earliest;
        }
      }

      // Sort by actual photo capture dates (oldest first)
      campanhasComFotos.sort((a, b) {
        final da = photoDates[a] ?? DateTime(2099);
        final db = photoDates[b] ?? DateTime(2099);
        return da.compareTo(db);
      });

      if (campanhasComFotos.isNotEmpty && mounted) {
        setState(() {
          _campaignPhotoDates = photoDates;
          // Auto-select: oldest photos = campanha 1, newest = campanha 2
          _campanha1Id = campanhasComFotos.first;
          if (campanhasComFotos.length > 1) {
            _campanha2Id = campanhasComFotos.last;
          }
        });
        _loadFotos();
      } else {
        setState(() => _isLoadingFotos = false);
      }
    } catch (e) {
      setState(() => _isLoadingFotos = false);
    }
  }

  void _onCampanha1Changed(String? id) {
    setState(() {
      _campanha1Id = id;
      _fotos1 = [];
    });
    _loadFotos();
  }

  void _onCampanha2Changed(String? id) {
    setState(() {
      _campanha2Id = id;
      _fotos2 = [];
    });
    _loadFotos();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comparação Temporal'),
        leading: isWide ? null : Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Comparação Temporal', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text('Compare fotos de diferentes campanhas da mesma torre para identificar evolução.',
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 24),

                  // Row 1: Linha + Torre
                  if (isWide)
                    Row(
                      children: [
                        Expanded(child: _buildLinhaDropdown()),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: _buildTorreDropdown()),
                      ],
                    )
                  else ...[
                    _buildLinhaDropdown(),
                    const SizedBox(height: 12),
                    _buildTorreDropdown(),
                  ],

                  const SizedBox(height: 16),

                  // Row 2: Campanhas
                  if (isWide)
                    Row(
                      children: [
                        Expanded(child: _buildCampanhaDropdown('Campanha 1 (Antes)', _campanha1Id, _onCampanha1Changed)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildCampanhaDropdown('Campanha 2 (Depois)', _campanha2Id, _onCampanha2Changed)),
                      ],
                    )
                  else ...[
                    _buildCampanhaDropdown('Campanha 1 (Antes)', _campanha1Id, _onCampanha1Changed),
                    const SizedBox(height: 12),
                    _buildCampanhaDropdown('Campanha 2 (Depois)', _campanha2Id, _onCampanha2Changed),
                  ],

                  const SizedBox(height: 24),

                  // Info about selected torre
                  if (_selectedTorre != null) ...[
                    Row(
                      children: [
                        Icon(MdiIcons.transmissionTower, color: AppColors.getCriticalityColor(_selectedTorre!.criticidadeAtual)),
                        const SizedBox(width: 8),
                        Text(_selectedTorre!.codigoTorre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                        CriticalityBadge(criticidade: _selectedTorre!.criticidadeAtual),
                        const Spacer(),
                        if (_isLoadingFotos) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Photo comparison side by side
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildPhotoColumn('Campanha 1', _campanha1Id, _fotos1)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildPhotoColumn('Campanha 2', _campanha2Id, _fotos2)),
                      ],
                    ),

                    // Evolution assessment
                    if (_campanha1Id != null && _campanha2Id != null && _fotos1.isNotEmpty && _fotos2.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildEvolutionSection(),
                    ],
                  ] else ...[
                    const SizedBox(height: 40),
                    const EmptyState(
                      icon: Icons.compare_rounded,
                      title: 'Selecione uma linha e torre',
                      subtitle: 'Escolha uma linha de transmissão, depois uma torre e duas campanhas para comparar.',
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildLinhaDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedLinhaId,
      decoration: const InputDecoration(labelText: 'Linha de Transmissão', prefixIcon: Icon(Icons.flash_on)),
      items: _linhas.map((l) => DropdownMenuItem(value: l.id, child: Text(l.nome))).toList(),
      onChanged: _onLinhaChanged,
    );
  }

  Widget _buildTorreDropdown() {
    if (_isLoadingTorres) {
      return InputDecorator(
        decoration: InputDecoration(labelText: 'Torre', prefixIcon: Icon(MdiIcons.transmissionTower)),
        child: Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Carregando torres...', style: TextStyle(color: AppColors.textMuted)),
        ]),
      );
    }
    return DropdownButtonFormField<String>(
      value: _selectedTorreId,
      decoration: InputDecoration(
        labelText: 'Torre',
        prefixIcon: Icon(MdiIcons.transmissionTower),
        helperText: _selectedLinhaId != null ? '${_torresForLinha.length} torres' : 'Selecione uma linha primeiro',
      ),
      items: _torresForLinha.map((t) => DropdownMenuItem(value: t.id, child: Text(t.codigoTorre))).toList(),
      onChanged: _selectedLinhaId != null ? _onTorreChanged : null,
    );
  }

  Widget _buildCampanhaDropdown(String label, String? value, void Function(String?) onChanged) {
    // Sort campaigns by actual photo capture dates (oldest first)
    final sortedCampanhas = List<Campanha>.from(_campanhas)
      ..sort((a, b) {
        final da = _campaignPhotoDates[a.id] ?? a.dataInicio ?? a.criadoEm ?? DateTime(2000);
        final db = _campaignPhotoDates[b.id] ?? b.dataInicio ?? b.criadoEm ?? DateTime(2000);
        return da.compareTo(db);
      });

    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.calendar_today)),
      items: [
        const DropdownMenuItem(value: null, child: Text('Nenhuma')),
        ...sortedCampanhas.map((c) {
          // Show actual photo date if available, otherwise campaign date
          final photoDate = _campaignPhotoDates[c.id];
          final dateStr = photoDate != null
              ? ' (Fotos: ${photoDate.toString().substring(0, 10)})'
              : c.dataInicio != null
                  ? ' (${c.dataInicio!.toString().substring(0, 10)})'
                  : '';
          return DropdownMenuItem(value: c.id, child: Text('${c.nome}$dateStr'));
        }),
      ],
      onChanged: onChanged,
    );
  }

  Widget _buildPhotoColumn(String label, String? campanhaId, List<Foto> fotos) {
    final campanha = campanhaId != null
        ? _campanhas.where((c) => c.id == campanhaId).firstOrNull
        : null;

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
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (fotos.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${fotos.length} fotos', style: const TextStyle(fontSize: 11, color: AppColors.primary)),
                ),
            ],
          ),
          if (campanha != null)
            Text(campanha.nome, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 12),

          if (campanhaId == null) ...[
            const SizedBox(
              height: 200,
              child: Center(child: Text('Selecione uma campanha', style: TextStyle(color: AppColors.textMuted))),
            ),
          ] else if (_isLoadingFotos) ...[
            const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
          ] else if (fotos.isEmpty) ...[
            SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_library_outlined, size: 40, color: AppColors.textMuted),
                    const SizedBox(height: 8),
                    const Text('Sem fotos desta torre nesta campanha', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Photo grid with real thumbnails
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: fotos.length > 6 ? 6 : fotos.length,
              itemBuilder: (context, index) {
                final foto = fotos[index];
                final imageUrl = SupabaseService.getPhotoUrl(foto.caminhoStorage);
                return GestureDetector(
                  onTap: () {
                    // Open fullscreen gallery starting at tapped photo
                    FullScreenImageViewer.openGallery(
                      context,
                      fotos.map((f) => f.caminhoStorage).toList(),
                      initialIndex: index,
                      titles: fotos.map((f) => f.dataHoraCaptura?.toString().substring(0, 16) ?? f.nomeArquivo).toList(),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.bgSurface,
                            child: const Icon(Icons.broken_image, color: AppColors.textMuted),
                          ),
                        ),
                        // Zoom hint icon
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.fullscreen, color: Colors.white70, size: 14),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            color: Colors.black54,
                            child: Text(
                              foto.dataHoraCaptura?.toString().substring(0, 10) ?? foto.nomeArquivo,
                              style: const TextStyle(color: Colors.white, fontSize: 9),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (fotos.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('+${fotos.length - 6} mais fotos', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEvolutionSection() {
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
          const Text('Avaliação da Evolução', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            children: [
              _evolutionChip('piorou', 'Piorou', AppColors.error),
              const SizedBox(width: 12),
              _evolutionChip('sem_alteracao', 'Sem Alteração', AppColors.info),
              const SizedBox(width: 12),
              _evolutionChip('melhorou', 'Melhorou', AppColors.success),
            ],
          ),
          const SizedBox(height: 16),
          const TextField(
            decoration: InputDecoration(
              labelText: 'Observações da comparação',
              hintText: 'Descreva as mudanças observadas...',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.save_rounded),
            label: const Text('Registrar Evolução'),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Evolução registrada!'), backgroundColor: AppColors.success),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _evolutionChip(String value, String label, Color color) {
    final isSelected = _evolution == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (v) => setState(() => _evolution = value),
      selectedColor: color.withValues(alpha: 0.3),
      labelStyle: TextStyle(
        color: isSelected ? color : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}
