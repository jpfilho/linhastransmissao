import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../../shared/models/linha.dart';
import '../models/torre.dart';

class TorreListView extends StatefulWidget {
  const TorreListView({super.key});

  @override
  State<TorreListView> createState() => _TorreListViewState();
}

class _TorreListViewState extends State<TorreListView> {
  String _searchQuery = '';
  String? _filterLinha;
  List<Torre> _allTowers = [];
  List<Linha> _linhas = [];
  bool _isLoading = true;

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
    ]);
    setState(() {
      _allTowers = results[0] as List<Torre>;
      _linhas = results[1] as List<Linha>
        ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      _isLoading = false;
    });
  }

  List<Torre> get _filteredTowers {
    var towers = _allTowers;
    if (_searchQuery.isNotEmpty) {
      towers = towers.where((t) =>
          t.codigoTorre.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (t.descricao?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
      ).toList();
    }
    if (_filterLinha != null) {
      towers = towers.where((t) => t.linhaId == _filterLinha).toList();
    }
    // Sort ascending by codigoTorre with natural numeric ordering
    towers.sort((a, b) => _naturalCompare(a.codigoTorre, b.codigoTorre));
    return towers;
  }

  /// Natural sort: compares strings with embedded numbers naturally
  /// e.g. "TSAPRIU1 2-1" < "TSAPRIU1 10-1"
  int _naturalCompare(String a, String b) {
    final regExp = RegExp(r'(\d+)|(\D+)');
    final partsA = regExp.allMatches(a).toList();
    final partsB = regExp.allMatches(b).toList();
    for (int i = 0; i < partsA.length && i < partsB.length; i++) {
      final pa = partsA[i].group(0)!;
      final pb = partsB[i].group(0)!;
      final na = int.tryParse(pa);
      final nb = int.tryParse(pb);
      int cmp;
      if (na != null && nb != null) {
        cmp = na.compareTo(nb);
      } else {
        cmp = pa.compareTo(pb);
      }
      if (cmp != 0) return cmp;
    }
    return partsA.length.compareTo(partsB.length);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final towers = _filteredTowers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Torres'),
        leading: isWide ? null : Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData, tooltip: 'Atualizar'),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('${towers.length} torres', style: const TextStyle(color: AppColors.textMuted, fontSize: 13))),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filters
                Container(
                  padding: const EdgeInsets.all(16),
                  color: AppColors.bgSurface,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Buscar torre...',
                            prefixIcon: Icon(Icons.search, size: 20),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _filterLinha,
                          decoration: const InputDecoration(labelText: 'Linha', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Todas')),
                            ..._linhas.map((l) => DropdownMenuItem(value: l.id, child: Text(l.codigo ?? l.nome))),
                          ],
                          onChanged: (v) => setState(() => _filterLinha = v),
                        ),
                      ),
                    ],
                  ),
                ),
                // Tower list
                Expanded(
                  child: towers.isEmpty
                      ? EmptyState(icon: MdiIcons.transmissionTower, title: 'Nenhuma torre encontrada')
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: towers.length,
                          itemBuilder: (context, index) => _buildTowerCard(towers[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildTowerCard(Torre torre) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => context.go('/torres/${torre.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.getCriticalityColor(torre.criticidadeAtual).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  MdiIcons.transmissionTower,
                  color: AppColors.getCriticalityColor(torre.criticidadeAtual),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(torre.codigoTorre, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        CriticalityBadge(criticidade: torre.criticidadeAtual, compact: true),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (torre.linhaNome != null)
                      Text(torre.linhaNome!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Text(
                      '${torre.tipo ?? "—"} • ${torre.latitude.toStringAsFixed(4)}, ${torre.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
