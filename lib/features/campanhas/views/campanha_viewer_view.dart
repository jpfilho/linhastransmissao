import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/services/ai_service.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../../shared/widgets/image_viewer.dart';
import '../../../shared/models/linha.dart';
import '../../../shared/models/campanha.dart';
import '../../fotos/models/foto.dart';
import '../../fotos/views/photo_editor_view.dart';
import '../../supressao/widgets/visual_layout_editor.dart';
import '../../supressao/widgets/torre_chat_widget.dart';
import '../../torres/models/torre.dart';

class CampanhaViewerView extends StatefulWidget {
  const CampanhaViewerView({super.key});

  @override
  State<CampanhaViewerView> createState() => _CampanhaViewerViewState();
}

class _CampanhaViewerViewState extends State<CampanhaViewerView> {
  // Selection state
  String? _selectedCampanhaId;
  String? _selectedLinhaId;

  // Data
  List<Campanha> _campanhas = [];
  List<Linha> _linhas = [];
  List<Linha> _linhasDisponiveis = [];
  bool _isLoading = true;
  bool _isLoadingLinhas = false;

  // Photo viewer state
  bool _isLoadingFotos = false;
  List<_TorreGroup> _torreGroups = [];
  int _currentGroupIndex = 0;
  int _currentPhotoIndex = 0;
  late PageController _pageController;

  // Global flat list mapping
  List<_FlatEntry> _flatEntries = [];
  int _globalIndex = 0;

  // Suppression data per tower (torreId -> list of records)
  Map<String, List<Map<String, dynamic>>> _supressaoByTorre = {};
  
  // Track photos where user toggled to view ORIGINAL instead of EDITED version
  final Set<String> _viewingOriginals = {};
  
  // Controls the display of the full-screen suppression panel overlay
  bool _isSupressaoFullscreen = false;
  
  // Controls the main viewing mode ('fotos', 'tabela', 'global')
  String _viewMode = 'fotos';

  // Moondream
  bool _isMoondreamRunning = false;
  Uint8List? _moondreamImageBytes;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadInitialData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      SupabaseService.getCampanhas(),
      SupabaseService.getLinhas(),
    ]);
    setState(() {
      _campanhas = results[0] as List<Campanha>;
      _linhas = results[1] as List<Linha>;
      _linhasDisponiveis = []; // Start empty until a campaign is selected
      _isLoading = false;
    });
  }

  Future<void> _loadFotos({bool retainPosition = false}) async {
    if (_selectedCampanhaId == null || _selectedLinhaId == null) return;
    setState(() => _isLoadingFotos = true);

    final fotos = await SupabaseService.getFotos(
      campanhaId: _selectedCampanhaId,
      linhaId: _selectedLinhaId,
    );

    // Group by torre
    final grouped = <String?, List<Foto>>{};
    for (final f in fotos) {
      grouped.putIfAbsent(f.torreId, () => []).add(f);
    }

    // Build sorted groups
    final groups = <_TorreGroup>[];
    for (final entry in grouped.entries) {
      final torreId = entry.key;
      final torreCode = entry.value.first.torreCodigo ?? 'Sem torre';
      groups.add(_TorreGroup(
        torreId: torreId,
        codigoTorre: torreCode,
        fotos: entry.value,
      ));
    }
    groups.sort((a, b) => _naturalCompare(a.codigoTorre, b.codigoTorre));

    // Build flat index
    final flat = <_FlatEntry>[];
    for (int g = 0; g < groups.length; g++) {
      for (int p = 0; p < groups[g].fotos.length; p++) {
        flat.add(_FlatEntry(groupIndex: g, photoIndex: p));
      }
    }

    final int previousGlobalIndex = _globalIndex;

    setState(() {
      _torreGroups = groups;
      _flatEntries = flat;
      if (!retainPosition) {
        _currentGroupIndex = 0;
        _currentPhotoIndex = 0;
        _globalIndex = 0;
      } else {
        _globalIndex = previousGlobalIndex.clamp(0, flat.isEmpty ? 0 : flat.length - 1);
        if (flat.isNotEmpty) {
          _currentGroupIndex = flat[_globalIndex].groupIndex;
          _currentPhotoIndex = flat[_globalIndex].photoIndex;
        }
      }
      _isLoadingFotos = false;
      if (!retainPosition) {
         _supressaoByTorre = {};
      }
    });

    // Reset page controller
    if (_pageController.hasClients) {
      if (!retainPosition) {
        _pageController.jumpToPage(0);
      } else {
        _pageController.jumpToPage(_globalIndex);
      }
    } else {
      _pageController.dispose();
      _pageController = PageController(initialPage: retainPosition ? _globalIndex : 0);
    }

    // Pre-load suppression data for all towers in this line
    if (!retainPosition) {
      _loadSupressaoData();
    }

    // Load suppression for the first tower
    if (groups.isNotEmpty && groups[0].torreId != null && !retainPosition) {
      _loadSupressaoForTorre(groups[0].torreId!);
    }
  }

  Future<void> _loadSupressaoData() async {
    if (_selectedLinhaId == null) return;
    try {
      final data = await SupabaseService.getSupressaoByLinha(_selectedLinhaId!);
      final map = <String, List<Map<String, dynamic>>>{};
      for (final record in data) {
        final torreId = record['torre_id'] as String?;
        if (torreId != null) {
          map.putIfAbsent(torreId, () => []).add(record);
        }
      }
      if (mounted) setState(() => _supressaoByTorre = map);
    } catch (_) {}
  }

  Future<void> _loadSupressaoForTorre(String torreId) async {
    if (_supressaoByTorre.containsKey(torreId)) return;
    try {
      final data = await SupabaseService.getSupressaoByTorre(torreId);
      if (mounted) {
        setState(() {
          _supressaoByTorre[torreId] = data;
        });
      }
    } catch (_) {}
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

  void _onPageChanged(int globalIdx) {
    if (globalIdx < 0 || globalIdx >= _flatEntries.length) return;
    final entry = _flatEntries[globalIdx];
    setState(() {
      _globalIndex = globalIdx;
      _currentGroupIndex = entry.groupIndex;
      _currentPhotoIndex = entry.photoIndex;
    });
    // Lazy load suppression for new tower
    final torreId = _torreGroups[entry.groupIndex].torreId;
    if (torreId != null) _loadSupressaoForTorre(torreId);
  }

  void _goToTorre(int groupIndex) {
    final idx = _flatEntries.indexWhere((e) => e.groupIndex == groupIndex);
    if (idx >= 0) {
      _pageController.animateToPage(idx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  Foto? get _currentFoto {
    if (_torreGroups.isEmpty) return null;
    final group = _torreGroups[_currentGroupIndex];
    if (_currentPhotoIndex >= group.fotos.length) return null;
    return group.fotos[_currentPhotoIndex];
  }

  List<Map<String, dynamic>> get _currentSupressao {
    if (_torreGroups.isEmpty) return [];
    final torreId = _torreGroups[_currentGroupIndex].torreId;
    if (torreId == null) return [];
    return _supressaoByTorre[torreId] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Campanhas — Visualização Sequencial'),
        leading: isWide
            ? null
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        actions: [
          if (_torreGroups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'fotos', icon: Icon(Icons.photo_library), label: Text('Fotos')),
                  ButtonSegment(value: 'tabela', icon: Icon(Icons.table_rows), label: Text('Tabela')),
                  ButtonSegment(value: 'global', icon: Icon(Icons.blur_linear), label: Text('Global')),
                ],
                selected: {_viewMode},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() => _viewMode = newSelection.first);
                },
                style: SegmentedButton.styleFrom(
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    _buildFilterBar(isWide),
                    const Divider(height: 1, color: AppColors.border),
                    Expanded(
                      child: _torreGroups.isEmpty
                          ? _buildEmptyState()
                          : _viewMode == 'global'
                              ? _buildGlobalTable()
                              : _viewMode == 'tabela'
                                  ? _buildMacroTable()
                              : Row(
                                  children: [
                                    if (isWide) _buildTowerSidebar(),
                                    Expanded(
                                      flex: 6,
                                      child: Column(
                                        children: [
                                          Expanded(child: _buildPhotoViewer()),
                                          if (isWide) Container(height: 1, color: AppColors.border),
                                          if (isWide) _buildVisualEditorPanel(),
                                        ],
                                      ),
                                    ),
                                    if (isWide) Container(width: 1, color: AppColors.border),
                                    if (isWide) Expanded(flex: 4, child: _buildSupressaoPanel()),
                                  ],
                                ),
                    ),
                    if (!isWide && _torreGroups.isNotEmpty) _buildTowerStrip(),
                  ],
                ),
                if (_isSupressaoFullscreen)
                  Positioned.fill(
                    child: _buildFullscreenSupressaoOverlay(),
                  ),
              ],
            ),
    );
  }

  Widget _buildFullscreenSupressaoOverlay() {
    final torreStr = _torreGroups[_currentGroupIndex].codigoTorre;
    
    return Container(
      color: AppColors.bgDark,
      child: Column(
        children: [
          // Header Overlay
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            color: AppColors.bgElevated,
            child: Row(
              children: [
                const Icon(Icons.zoom_out_map, size: 24, color: AppColors.accent),
                const SizedBox(width: 12),
                Text(
                  'Mapeamento Torre $torreStr',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: () => setState(() => _isSupressaoFullscreen = false),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Comprimir Tela'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          // Body Overlay (Expanded with infinite width logic from Supressao)
          Expanded(
            child: _currentSupressao.isEmpty
                ? const Center(
                    child: Text('Sem mapeamento disponível.', style: TextStyle(color: AppColors.textMuted)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
                    itemCount: _currentSupressao.length,
                    itemBuilder: (context, index) => _buildSupressaoCard(_currentSupressao[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool isWide) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.bgCard,
      child: isWide
          ? Row(
              children: [
                Expanded(child: _buildCampanhaDropdown()),
                const SizedBox(width: 12),
                Expanded(child: _buildLinhaDropdown()),
                const SizedBox(width: 12),
                if (_flatEntries.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_torreGroups.length} torres â€¢ ${_flatEntries.length} fotos',
                      style: const TextStyle(fontSize: 13, color: AppColors.primaryLight),
                    ),
                  ),
              ],
            )
          : Column(
              children: [
                _buildCampanhaDropdown(),
                const SizedBox(height: 8),
                _buildLinhaDropdown(),
              ],
            ),
    );
  }

  Widget _buildCampanhaDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedCampanhaId,
      decoration: const InputDecoration(
        labelText: 'Campanha',
        prefixIcon: Icon(Icons.campaign_rounded),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: _campanhas.map((c) {
        final dateStr = c.dataInicio != null ? ' (${c.dataInicio!.toString().substring(0, 10)})' : '';
        return DropdownMenuItem(value: c.id, child: Text('${c.nome}$dateStr'));
      }).toList(),
      onChanged: (id) async {
        setState(() {
          _selectedCampanhaId = id;
          _selectedLinhaId = null;
          _torreGroups = [];
          _flatEntries = [];
          _isLoadingLinhas = true;
        });
        
        if (id != null) {
          try {
            final validIds = await SupabaseService.getLinhasIdsPorCampanha(id);
            if (mounted) {
              setState(() {
                _linhasDisponiveis = _linhas.where((l) => validIds.contains(l.id)).toList();
              });
            }
          } finally {
            if (mounted) setState(() => _isLoadingLinhas = false);
          }
        } else {
          if (mounted) {
            setState(() {
              _linhasDisponiveis = [];
              _isLoadingLinhas = false;
            });
          }
        }
      },
    );
  }

  Widget _buildLinhaDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedLinhaId,
      decoration: InputDecoration(
        labelText: _isLoadingLinhas ? 'Carregando opções...' : 'Linha de Transmissão',
        prefixIcon: _isLoadingLinhas
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
            : const Icon(Icons.power_rounded),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: _linhasDisponiveis.map((l) => DropdownMenuItem(value: l.id, child: Text(l.nome))).toList(),
      onChanged: (id) {
        setState(() {
          _selectedLinhaId = id;
          _torreGroups = [];
          _flatEntries = [];
        });
        if (id != null && _selectedCampanhaId != null) _loadFotos();
      },
    );
  }

  Widget _buildEmptyState() {
    if (_isLoadingFotos) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_selectedCampanhaId != null && _selectedLinhaId != null) {
      return const EmptyState(
        icon: Icons.photo_library_outlined,
        title: 'Nenhuma foto encontrada',
        subtitle: 'Não há fotos para esta campanha e linha.',
      );
    }
    return const EmptyState(
      icon: Icons.campaign_rounded,
      title: 'Selecione uma campanha e linha',
      subtitle: 'Escolha uma campanha e uma linha de transmissão para navegar pelas fotos torre a torre.',
    );
  }

  Widget _buildTowerSidebar() {
    return Container(
      width: 220,
      color: AppColors.bgCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('TORRES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.2)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _torreGroups.length,
              itemBuilder: (context, index) {
                final group = _torreGroups[index];
                final isActive = index == _currentGroupIndex;
                final hasSupressao = group.torreId != null && (_supressaoByTorre[group.torreId]?.isNotEmpty ?? false);
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isActive ? AppColors.primaryLight.withValues(alpha: 0.15) : null,
                  ),
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      MdiIcons.transmissionTower,
                      size: 18,
                      color: isActive ? AppColors.primaryLight : AppColors.textMuted,
                    ),
                    title: Text(
                      group.codigoTorre,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                        color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasSupressao)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.grass, size: 12, color: AppColors.success),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isActive ? AppColors.primaryLight.withValues(alpha: 0.2) : AppColors.bgElevated,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${group.fotos.length}',
                            style: TextStyle(fontSize: 10, color: isActive ? AppColors.primaryLight : AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                    onTap: () => _goToTorre(index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTowerStrip() {
    return Container(
      height: 52,
      color: AppColors.bgCard,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _torreGroups.length,
        itemBuilder: (context, index) {
          final group = _torreGroups[index];
          final isActive = index == _currentGroupIndex;
          return GestureDetector(
            onTap: () => _goToTorre(index),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? AppColors.primaryLight.withValues(alpha: 0.2) : AppColors.bgElevated,
                borderRadius: BorderRadius.circular(8),
                border: isActive ? Border.all(color: AppColors.primaryLight, width: 1.5) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(MdiIcons.transmissionTower, size: 14, color: isActive ? AppColors.primaryLight : AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    group.codigoTorre,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // DELETE SUPPRESSION RECORDS
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Future<void> _confirmDeleteSupressao(Map<String, dynamic> record) async {
    final estCodigo = record['est_codigo'] ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Registro'),
        content: Text('Deseja excluir o registro EST $estCodigo do mapeamento de roço?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await SupabaseService.deleteSupressao(record['id']);
      // Remove from local cache
      final torreId = _torreGroups[_currentGroupIndex].torreId;
      if (torreId != null && _supressaoByTorre.containsKey(torreId)) {
        setState(() {
          _supressaoByTorre[torreId]!.removeWhere((r) => r['id'] == record['id']);
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registro EST $estCodigo excluído'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _confirmDeleteAllSupressao() async {
    if (_selectedLinhaId == null) return;
    final linhaName = _linhas.where((l) => l.id == _selectedLinhaId).firstOrNull?.nome ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Todo Mapeamento'),
        content: Text('Deseja excluir TODOS os registros de mapeamento de roço da linha "$linhaName"?\n\nEsta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Excluir Tudo'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final count = await SupabaseService.deleteSupressaoByLinha(_selectedLinhaId!);
      setState(() => _supressaoByTorre = {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count registros excluídos'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // SUPPRESSION PANEL (right side)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Widget _buildSupressaoPanel() {
    final records = _currentSupressao;

    return Container(
      width: double.infinity,
      color: AppColors.bgCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.grass, size: 16, color: AppColors.success),
                const SizedBox(width: 6),
                const Text(
                  'MAPEAMENTO ROÇO',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.2),
                ),
                const Spacer(),
                if (records.isNotEmpty) ...[                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${records.length} ${records.length == 1 ? 'registro' : 'registros'}',
                      style: const TextStyle(fontSize: 10, color: AppColors.success),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => setState(() => _isSupressaoFullscreen = true),
                    child: Tooltip(
                      message: 'Expandir dados de roço para edição em tela cheia',
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.zoom_out_map, size: 16, color: AppColors.accent.withValues(alpha: 0.8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _confirmDeleteAllSupressao(),
                    child: Tooltip(
                      message: 'Excluir todos os registros desta linha',
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.delete_sweep, size: 16, color: AppColors.error.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          // Content
          Expanded(
            flex: 4,
            child: records.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.grass, size: 32, color: AppColors.textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 8),
                          const Text(
                            'Sem dados de roço\npara esta torre',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: records.length,
                    itemBuilder: (context, index) => _buildSupressaoCard(records[index]),
                  ),
          ),
          
          if (_torreGroups.isNotEmpty && _torreGroups[_currentGroupIndex].torreId != null)
            Expanded(
              flex: 5,
              child: TorreChatWidget(
                key: ValueKey('chat_\${_torreGroups[_currentGroupIndex].torreId}'),
                torreId: _torreGroups[_currentGroupIndex].torreId!,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVisualEditorPanel() {
    final records = _currentSupressao;
    final validRecords = records.where((r) => (r['vao_frente_m']?.toDouble() ?? 0) > 0).toList();
    if (validRecords.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: AppColors.bgSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: validRecords.map((record) {
          final vaoM = record['vao_frente_m']?.toDouble() ?? 0;
          final descricao = record['descricao_servico'] as String?;
          final est = record['est_codigo'] ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (validRecords.length > 1) 
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text('EST $est', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                  ),
                VisualLayoutEditor(
                  key: ValueKey('main_visual_editor_${record['id']}'),
                  mapeamentoId: record['id'].toString(), 
                  vaoM: vaoM,
                  descricaoServico: descricao ?? '',
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSupressaoCard(Map<String, dynamic> record) {
    final estCodigo = record['est_codigo'] ?? '';
    final prioridade = record['prioridade'] as String?;
    final concluido = record['roco_concluido'] == true;
    final descricao = record['descricao_servico'] as String?;
    final atende = record['atende'] as String?;
    final vaoM = record['vao_frente_m']?.toDouble();
    final larguraM = record['largura_m']?.toDouble();
    final mapMecExt = record['map_mec_extensao']?.toDouble();
    final mapManExt = record['map_man_extensao']?.toDouble();
    final execMecExt = record['exec_mec_extensao']?.toDouble();
    final execManExt = record['exec_man_extensao']?.toDouble();

    Color prioridadeColor;
    switch (prioridade) {
      case 'P1':
        prioridadeColor = AppColors.error;
        break;
      case 'P2':
        prioridadeColor = AppColors.warning;
        break;
      default:
        prioridadeColor = AppColors.success;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // EST + Priority + Status + Delete
          Row(
            children: [
              Text(
                'EST $estCodigo',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (prioridade != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: prioridadeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    prioridade,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: prioridadeColor),
                  ),
                ),
              const SizedBox(width: 6),
              Icon(
                concluido ? Icons.check_circle : Icons.pending,
                size: 16,
                color: concluido ? AppColors.success : AppColors.textMuted,
              ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _confirmDeleteSupressao(record),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.delete_outline, size: 15, color: AppColors.error.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ),

          // Dimensions
          if (vaoM != null || larguraM != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (vaoM != null) _infoChip('Vão', '${vaoM.toStringAsFixed(0)}m'),
                if (vaoM != null && larguraM != null) const SizedBox(width: 6),
                if (larguraM != null) _infoChip('Larg.', '${larguraM.toStringAsFixed(0)}m'),
              ],
            ),
          ],

          // Mapping vs Execution
          if ((mapMecExt ?? 0) > 0 || (mapManExt ?? 0) > 0 || (execMecExt ?? 0) > 0 || (execManExt ?? 0) > 0) ...[
            const SizedBox(height: 8),
            const Text('Mapeamento / Execução:', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            const SizedBox(height: 4),
            if ((mapMecExt ?? 0) > 0 || (execMecExt ?? 0) > 0)
              _progressRow('Mecanizado', mapMecExt, execMecExt),
            if ((mapManExt ?? 0) > 0 || (execManExt ?? 0) > 0)
              _progressRow('Manual', mapManExt, execManExt),
          ],

          // Atende
          if (atende != null && atende.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('Atende: ', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                Text(atende, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ],

          // Description (the main thing the user asked for)
          if (descricao != null && descricao.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notes, size: 12, color: AppColors.accent),
                      const SizedBox(width: 4),
                      const Text('Observações', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accent)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    descricao,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),
          ],

        ],
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _progressRow(String label, double? mapped, double? executed) {
    final m = mapped ?? 0;
    final e = executed ?? 0;
    final pct = m > 0 ? (e / m).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: AppColors.bgElevated,
                valueColor: AlwaysStoppedAnimation(pct >= 1.0 ? AppColors.success : AppColors.primaryLight),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${e.toStringAsFixed(0)}/${m.toStringAsFixed(0)}m',
            style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // PHOTO VIEWER (center)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Widget _buildPhotoViewer() {
    final totalPhotos = _flatEntries.length;
    final currentGroup = _torreGroups.isNotEmpty ? _torreGroups[_currentGroupIndex] : null;
    final foto = _currentFoto;

    return Column(
      children: [
        // Header info bar
        if (currentGroup != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.bgElevated.withValues(alpha: 0.5),
            child: Row(
              children: [
                Icon(MdiIcons.transmissionTower, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  currentGroup.codigoTorre,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Foto ${_currentPhotoIndex + 1} de ${currentGroup.fotos.length}',
                    style: const TextStyle(fontSize: 11, color: AppColors.accent),
                  ),
                ),
                const Spacer(),
                Text(
                  'Torre ${_currentGroupIndex + 1}/${_torreGroups.length}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${_globalIndex + 1}/$totalPhotos total)',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        // Photo area with PageView
        Expanded(
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: totalPhotos,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final entry = _flatEntries[index];
                  final f = _torreGroups[entry.groupIndex].fotos[entry.photoIndex];
                  
                  final hasEdicao = f.arquivoEditadoUrl != null && f.arquivoEditadoUrl!.isNotEmpty;
                  final showOriginal = _viewingOriginals.contains(f.id);
                  
                  final activeStoragePath = (hasEdicao && !showOriginal) ? f.arquivoEditadoUrl! : f.caminhoStorage;
                  final imageUrl = SupabaseService.getPhotoUrl(activeStoragePath);
                  
                  return GestureDetector(
                    onTap: () {
                      final group = _torreGroups[entry.groupIndex];
                      FullScreenImageViewer.openGallery(
                        context,
                        group.fotos.map((foto) {
                            final hasE = foto.arquivoEditadoUrl != null && foto.arquivoEditadoUrl!.isNotEmpty;
                            final sO = _viewingOriginals.contains(foto.id);
                            return (hasE && !sO) ? foto.arquivoEditadoUrl! : foto.caminhoStorage;
                        }).toList(),
                        initialIndex: entry.photoIndex,
                        titles: group.fotos.map((foto) => '${group.codigoTorre} — ${foto.dataHoraCaptura?.toString().substring(0, 16) ?? foto.nomeArquivo}').toList(),
                      );
                    },
                    child: Container(
                      color: AppColors.bgDark,
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 8.0,
                        clipBehavior: Clip.none,
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
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.broken_image, size: 48, color: AppColors.textMuted),
                                SizedBox(height: 8),
                                Text('Erro ao carregar imagem', style: TextStyle(color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Navigation arrows
              if (totalPhotos > 1) ...[
                if (_globalIndex > 0)
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
                if (_globalIndex < totalPhotos - 1)
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
              
              // Editing Options Overlay
              if (totalPhotos > 0)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Toggle Button if Edition Exists
                      if (_flatEntries.isNotEmpty && _torreGroups[_flatEntries[_globalIndex].groupIndex].fotos[_flatEntries[_globalIndex].photoIndex].arquivoEditadoUrl != null)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: AppColors.bgSurface.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                                onTap: () => setState(() => _viewingOriginals.add(_torreGroups[_flatEntries[_globalIndex].groupIndex].fotos[_flatEntries[_globalIndex].photoIndex].id)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _viewingOriginals.contains(_torreGroups[_flatEntries[_globalIndex].groupIndex].fotos[_flatEntries[_globalIndex].photoIndex].id) ? AppColors.primary : Colors.transparent,
                                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                                  ),
                                  child: Text('Original', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _viewingOriginals.contains(_torreGroups[_flatEntries[_globalIndex].groupIndex].fotos[_flatEntries[_globalIndex].photoIndex].id) ? Colors.white : AppColors.textMuted)),
                                ),
                              ),
                              InkWell(
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                                onTap: () => setState(() => _viewingOriginals.remove(_torreGroups[_flatEntries[_globalIndex].groupIndex].fotos[_flatEntries[_globalIndex].photoIndex].id)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: !_viewingOriginals.contains(_torreGroups[_flatEntries[_globalIndex].groupIndex].fotos[_flatEntries[_globalIndex].photoIndex].id) ? AppColors.success : Colors.transparent,
                                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                                  ),
                                  child: Text('Editada', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: !_viewingOriginals.contains(_torreGroups[_flatEntries[_globalIndex].groupIndex].fotos[_flatEntries[_globalIndex].photoIndex].id) ? Colors.white : AppColors.textMuted)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Moondream mapping button
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'btn_moondream',
                        backgroundColor: Colors.green.shade700,
                        tooltip: 'Mapear Vegetação com Moondream 3',
                        onPressed: _isMoondreamRunning ? null : () => _triggerMoondreamOnCurrentFoto(),
                        child: _isMoondreamRunning
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.layers, color: Colors.white, size: 18),
                      ),
                      // Association button
                      const SizedBox(width: 8),
                      if (_flatEntries.isNotEmpty)
                        FloatingActionButton.small(
                          heroTag: 'btn_associate_photo',
                          backgroundColor: AppColors.warning,
                          tooltip: 'Corrigir Associação da Foto',
                          onPressed: () {
                            final currentEntry = _flatEntries[_globalIndex];
                            final fotoToEdit = _torreGroups[currentEntry.groupIndex].fotos[currentEntry.photoIndex];
                            _showAssociationDialog(context, fotoToEdit);
                          },
                          child: const Icon(Icons.link, color: Colors.white, size: 18),
                        ),
                      // Edit Photo Button
                      const SizedBox(width: 8),                      if (_flatEntries.isNotEmpty)
                        FloatingActionButton.small(
                          heroTag: 'btn_edit_photo',
                          backgroundColor: AppColors.primary,
                          onPressed: () async {
                            final currentEntry = _flatEntries[_globalIndex];
                            final fotoToEdit = _torreGroups[currentEntry.groupIndex].fotos[currentEntry.photoIndex];
                            final urlToEdit = SupabaseService.getPhotoUrl(fotoToEdit.caminhoStorage);
                            
                            final edited = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => PhotoEditorView(
                                  fotoId: fotoToEdit.id,
                                  imageUrl: urlToEdit,
                                  originalStoragePath: fotoToEdit.caminhoStorage ?? '',
                                  editedStoragePath: fotoToEdit.arquivoEditadoUrl,
                                ),
                              ),
                            );
                            
                            if (edited == true) {
                              // Ensure we clear the original toggle preference so the user sees the new edition immediately
                              _viewingOriginals.remove(fotoToEdit.id);
                              // Reload DB data to get new arquivoEditadoUrl without losing position
                              _loadFotos(retainPosition: true); 
                            }
                          },
                          child: const Icon(Icons.edit, color: Colors.white, size: 18),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Photo metadata strip
        if (foto != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.bgCard,
            child: Row(
              children: [
                const Icon(Icons.photo_camera, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    foto.nomeArquivo,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (foto.dataHoraCaptura != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.access_time, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    foto.dataHoraCaptura!.toString().substring(0, 16),
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
                if (foto.distanciaTorreM != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.straighten, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    '${foto.distanciaTorreM!.toStringAsFixed(0)}m',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.fullscreen, size: 20),
                  tooltip: 'Tela cheia',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    final group = _torreGroups[_currentGroupIndex];
                    FullScreenImageViewer.openGallery(
                      context,
                      group.fotos.map((f) => f.caminhoStorage).toList(),
                      initialIndex: _currentPhotoIndex,
                      titles: group.fotos.map((f) => '${group.codigoTorre} — ${f.nomeArquivo}').toList(),
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _triggerMoondreamOnCurrentFoto() async {
    if (_flatEntries.isEmpty) return;
    final entry = _flatEntries[_globalIndex];
    final foto = _torreGroups[entry.groupIndex].fotos[entry.photoIndex];
    final torreId = _torreGroups[entry.groupIndex].torreId;
    if (torreId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Esta foto não está associada a uma torre.'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    setState(() => _isMoondreamRunning = true);
    try {
      // Get suppression data using actual columns (no 'segmentos' column exists)
      final supressao = await SupabaseService.client
          .from('mapeamento_supressao')
          .select('vao_frente_m, largura_m, map_mec_extensao, map_man_extensao, descricao_servico')
          .eq('torre_id', torreId)
          .maybeSingle();

      List<Map<String, dynamic>> segments = [];
      double vaoM = 100.0;
      double larguraM = 40.0;

      if (supressao != null) {
        vaoM = (supressao['vao_frente_m'] as num?)?.toDouble() ?? 100.0;
        larguraM = (supressao['largura_m'] as num?)?.toDouble() ?? 40.0;
        final mecExt = (supressao['map_mec_extensao'] as num?)?.toDouble() ?? 0.0;
        final manExt = (supressao['map_man_extensao'] as num?)?.toDouble() ?? 0.0;

        // Build segments from the raw extensao fields
        double cursor = 0;
        if (mecExt > 0) {
          segments.add({'tipo': 'mecanizado', 'inicio': cursor.toInt(), 'fim': (cursor + mecExt).toInt()});
          cursor += mecExt;
        }
        if (manExt > 0) {
          segments.add({'tipo': 'manual', 'inicio': cursor.toInt(), 'fim': (cursor + manExt).toInt()});
          cursor += manExt;
        }
        // If there's remaining vao not accounted for
        if (cursor < vaoM && vaoM > 0) {
          segments.add({'tipo': 'manual', 'inicio': cursor.toInt(), 'fim': vaoM.toInt()});
        }
        // Fallback: treat entire vao as manual if nothing defined
        if (segments.isEmpty && vaoM > 0) {
          segments.add({'tipo': 'manual', 'inicio': 0, 'fim': vaoM.toInt()});
        }
      }

      if (segments.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nenhum segmento de mapeamento encontrado para esta torre.'),
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
        torreCodigo: _torreGroups[entry.groupIndex].codigoTorre,
      );

      if (bytes != null && mounted) {
        setState(() {
          _moondreamImageBytes = bytes;
          _isMoondreamRunning = false;
        });
        _showMoondreamDialog(segments, vaoM, _torreGroups[entry.groupIndex].codigoTorre);
      } else {
        setState(() => _isMoondreamRunning = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Serviço Moondream indisponível.'),
            backgroundColor: AppColors.error,
          ));
        }
      }
    } catch (e) {
      setState(() => _isMoondreamRunning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro Moondream: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  void _showMoondreamDialog(List<Map<String, dynamic>> segments, double vaoM, String codigoTorre) {
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
                          Text('$codigoTorre — Mapeamento Moondream 3',
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          Text('Vão: ${vaoM.toStringAsFixed(0)}m  •  ${segments.length} segmento(s)',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Wrap(
                  spacing: 8, runSpacing: 6,
                  children: segments.map((seg) {
                    final tipo = seg['tipo'] as String? ?? 'manual';
                    final inicio = seg['inicio'] as num? ?? 0;
                    final fim = seg['fim'] as num? ?? vaoM;
                    final color = colorMap[tipo] ?? Colors.grey;
                    final label = tipo[0].toUpperCase() + tipo.substring(1);
                    return Chip(
                      avatar: CircleAvatar(backgroundColor: color, radius: 8),
                      label: Text('$label: ${inicio.toInt()}–${fim.toInt()}m', style: const TextStyle(fontSize: 11)),
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

  Widget _navButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Icon(icon, color: Colors.white70, size: 28),
      ),
    );
  }

  Widget _buildMacroTable() {
    final allRecords = <Map<String, dynamic>>[];
    for (final group in _torreGroups) {
      if (group.torreId != null && _supressaoByTorre.containsKey(group.torreId)) {
        allRecords.addAll(_supressaoByTorre[group.torreId]!);
      }
    }

    if (allRecords.isEmpty) {
      return const Center(child: Text('Nenhum dado de mapeamento nesta linha.'));
    }

    return Container(
      color: AppColors.bgCard,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: allRecords.length,
        itemBuilder: (context, index) {
          final record = allRecords[index];
          final est = record['est_codigo'] ?? '';
          final prioridade = record['prioridade'] as String?;
          final atende = record['atende'] as String?;
          final vaoM = record['vao_frente_m']?.toDouble() ?? 0.0;
          final descricao = record['descricao_servico'] as String?;
          
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('EST $est', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const Spacer(),
                          if (prioridade != null) 
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                              child: Text(prioridade, style: const TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.bold)),
                            ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _confirmDeleteSupressao(record),
                            child: const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Vão: ${vaoM.toStringAsFixed(0)}m', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      if (atende != null && atende.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Atende: $atende', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        ),
                      if (descricao != null && descricao.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Obs: $descricao', style: const TextStyle(color: AppColors.accent, fontSize: 11), maxLines: 3, overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                Container(width: 1, height: 80, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 16)),
                Expanded(
                  flex: 7,
                  child: (vaoM > 0) 
                    ? VisualLayoutEditor(
                        key: ValueKey('table_visual_editor_${record['id']}'),
                        mapeamentoId: record['id'].toString(), 
                        vaoM: vaoM,
                        descricaoServico: descricao ?? '',
                      )
                    : const Center(child: Text('Vão inválido para esquema visual', style: TextStyle(color: AppColors.textMuted))),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGlobalTable() {
    return Container(
      color: AppColors.bgSurface,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _torreGroups.length,
        itemBuilder: (context, index) {
          final group = _torreGroups[index];
          final torreId = group.torreId;
          final supressoes = (torreId != null && _supressaoByTorre.containsKey(torreId)) 
              ? _supressaoByTorre[torreId]! 
              : <Map<String, dynamic>>[];

          // Para a visão global, vamos renderizar todas as supressões atreladas à torre.
          // Geralmente é uma, mas iteramos por segurança.
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    group.codigoTorre,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: (supressoes.isEmpty)
                      ? const ReadonlySpanBarWidget(mapeamentoId: 'empty', maxMeters: 1000) // Sem dados reais
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: supressoes.map((record) {
                            final rawVao = record['vao_frente_m']?.toDouble() ?? 0.0;
                            final double vaoM = rawVao > 0 ? rawVao : 1000.0;
                            final descricao = record['descricao_servico'] as String? ?? '';
                            
                            if (record['id'] != null) {
                              final tooltipText = descricao.isNotEmpty 
                                  ? '${group.codigoTorre}\n$descricao' 
                                  : group.codigoTorre;

                              final spanBarWidget = ReadonlySpanBarWidget(
                                mapeamentoId: record['id'].toString(), 
                                maxMeters: vaoM,
                                baseTooltipText: tooltipText,
                              );
                              
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2.0),
                                child: spanBarWidget,
                              );
                            }
                              return const SizedBox();
                            }).toList(),
                          ),
                  ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    final flatIndex = _flatEntries.indexWhere((e) => e.groupIndex == index);
                    if (flatIndex != -1) {
                      setState(() {
                        _viewMode = 'fotos';
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_pageController.hasClients) {
                          _pageController.jumpToPage(flatIndex);
                        }
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                    child: Tooltip(
                      message: 'Visualizar Fotos',
                      child: Icon(MdiIcons.cameraOutline, color: AppColors.accent, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ASSOCIATION LOGIC (Ported from FotoDetailView)
  // ════════════════════════════════════════════════════════════════════════════

  void _showAssociationDialog(BuildContext context, Foto foto) {
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
                                            _associateTorre(foto, td.torre);
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
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                const Spacer(),
                                if (!hasGps)
                                  const Text('A foto não possui GPS', style: TextStyle(fontSize: 11, color: AppColors.warning)),
                              ],
                            ),
                          ),
                          // List of towers
                          Expanded(
                            child: ListView.separated(
                              itemCount: torresWithDistance.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final td = torresWithDistance[index];
                                final t = td.torre;
                                return ListTile(
                                  leading: Icon(MdiIcons.transmissionTower, color: AppColors.getColorForLinha(t.linhaNome ?? t.linhaId)),
                                  title: Text(t.codigoTorre, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    'Linha: ${t.linhaNome ?? '-'}\n${hasGps ? 'Distância: ${td.distanceM.toStringAsFixed(1)} m' : 'Coordenadas: ${t.latitude}, ${t.longitude}'}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: const Icon(Icons.chevron_right, size: 20),
                                  isThreeLine: true,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _associateTorre(foto, t);
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

  void _associateTorre(Foto foto, Torre torre) async {
    try {
      await SupabaseService.updateFotoAssociation(
        fotoId: foto.id,
        torreId: torre.id,
        linhaId: torre.linhaId,
        torreCodigo: torre.codigoTorre,
        linhaNome: torre.linhaNome,
        distanciaM: foto.hasGps == true
            ? _haversineDistance(foto.latitude!, foto.longitude!, torre.latitude, torre.longitude)
            : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Foto associada à torre ${torre.codigoTorre}'), backgroundColor: AppColors.success),
        );
        _loadFotos(retainPosition: true); // Reload the campaign groups
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
    final c = 2 * asin(sqrt(a));
    return r * c;
  }
}

class ReadonlySpanBarWidget extends StatefulWidget {
  final String mapeamentoId;
  final double maxMeters;
  final String baseTooltipText;

  const ReadonlySpanBarWidget({
    super.key,
    required this.mapeamentoId,
    required this.maxMeters,
    this.baseTooltipText = '',
  });

  @override
  State<ReadonlySpanBarWidget> createState() => _ReadonlySpanBarWidgetState();
}

class _ReadonlySpanBarWidgetState extends State<ReadonlySpanBarWidget> {
  List<dynamic> _segmentos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSegments();
  }

  Future<void> _loadSegments() async {
    if (widget.mapeamentoId == 'empty') {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    
    try {
      final segs = await SupabaseService.getSupressaoLayoutVisual(widget.mapeamentoId);
      if (mounted && segs != null) {
        setState(() {
          _segmentos = segs;
        });
      }
    } catch (_) {
      // Ignora e deixa vazio
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String getStatusTextAndEmoji(String text) {
      switch (text) {
        case 'iniciado': return 'Iniciado 🔵';
        case 'concluido': return 'Concluído 🟢';
        case 'com_pendencias': return 'Pendência 🟠';
        case 'fiscalizado': return 'Fiscalizado ⭐';
        case 'nao_iniciado':
        default: return 'Não Iniciado ⚪';
      }
    }

    String getStatusEmoji(String text) {
      switch (text) {
        case 'iniciado': return '🔵';
        case 'concluido': return '🟢';
        case 'com_pendencias': return '🟠';
        case 'fiscalizado': return '⭐';
        case 'nao_iniciado':
        default: return '⚪';
      }
    }

    String finalTooltip = widget.baseTooltipText;
    if (_segmentos.isNotEmpty) {
      finalTooltip += '\n\n-- Segmentos --';
      for (var segData in _segmentos) {
        final String tipo = segData['tipo'] ?? 'Desconhecido';
        final status = segData['status'] as String? ?? 'nao_iniciado';
        final inicio = segData['inicio']?.toString() ?? '0';
        final fim = segData['fim']?.toString() ?? '0';
        final statusText = getStatusTextAndEmoji(status);
        finalTooltip += '\n${inicio}m a ${fim}m: ${tipo.toUpperCase()} ($statusText)';
      }
    }

    return Tooltip(
      message: finalTooltip.trim(),
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        height: 18,
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.border),
        ),
        child: _isLoading 
          ? const SizedBox() // Fica vazio/cinza enquando carrega
          : LayoutBuilder(
            builder: (context, constraints) {
              final double pxPerMeter = constraints.maxWidth / widget.maxMeters;
              return Stack(
                children: _segmentos.map((segData) {
                  final String tipo = segData['tipo'] ?? 'nao_rocar';
                  final double startM = (segData['inicio'] as num?)?.toDouble() ?? 0.0;
                  final double endM = (segData['fim'] as num?)?.toDouble() ?? 0.0;
                  
                  final leftPx = startM * pxPerMeter;
                  final widthPx = (endM - startM) * pxPerMeter;
                  
                  Color color;
                  switch (tipo) {
                    case 'manual': color = const Color(0xFFE67E22); break;
                    case 'mecanizado': color = const Color(0xFF8E44AD); break;
                    case 'seletivo': color = const Color(0xFF27AE60); break;
                    default: color = Colors.transparent;
                  }
                  final status = segData['status'] as String? ?? 'nao_iniciado';

                  return Positioned(
                    left: leftPx,
                    width: widthPx.clamp(0.0, double.infinity),
                    top: 0,
                    bottom: 0,
                    child: Container(
                      color: color.withValues(alpha: 0.9),
                      child: Center(
                        child: Text(
                          getStatusEmoji(status),
                          style: const TextStyle(fontSize: 8),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ),
    );
  }
}

// Internal models for grouping
class _TorreGroup {
  final String? torreId;
  final String codigoTorre;
  final List<Foto> fotos;

  _TorreGroup({
    required this.torreId,
    required this.codigoTorre,
    required this.fotos,
  });
}

class _FlatEntry {
  final int groupIndex;
  final int photoIndex;

  _FlatEntry({required this.groupIndex, required this.photoIndex});
}

class _TorreDistance {
  final Torre torre;
  final double distanceM;

  const _TorreDistance({required this.torre, required this.distanceM});
}

