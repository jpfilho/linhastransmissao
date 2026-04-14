import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/config/app_constants.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../anomalias/models/anomalia.dart';

class AnomaliaListView extends StatefulWidget {
  const AnomaliaListView({super.key});

  @override
  State<AnomaliaListView> createState() => _AnomaliaListViewState();
}

class _AnomaliaListViewState extends State<AnomaliaListView> {
  String? _filterTipo;
  String? _filterSeveridade;
  List<Anomalia> _allAnomalias = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final anomalias = await SupabaseService.getAnomalias();
    setState(() {
      _allAnomalias = anomalias;
      _isLoading = false;
    });
  }

  List<Anomalia> get _filteredAnomalias {
    var anomalias = _allAnomalias;
    if (_filterTipo != null) {
      anomalias = anomalias.where((a) => a.tipo == _filterTipo).toList();
    }
    if (_filterSeveridade != null) {
      anomalias = anomalias.where((a) => a.severidade == _filterSeveridade).toList();
    }
    return anomalias;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final anomalias = _filteredAnomalias;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anomalias'),
        leading: isWide ? null : Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData, tooltip: 'Atualizar'),
          TextButton.icon(
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Nova Anomalia'),
            onPressed: () => context.go('/anomalias/nova'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: AppColors.bgSurface,
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _filterTipo,
                          decoration: const InputDecoration(labelText: 'Tipo', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Todos')),
                            ...AppConstants.tiposAnomalia.map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(AppConstants.anomaliaLabels[t] ?? t),
                            )),
                          ],
                          onChanged: (v) => setState(() => _filterTipo = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _filterSeveridade,
                          decoration: const InputDecoration(labelText: 'Severidade', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('Todas')),
                            DropdownMenuItem(value: 'baixa', child: Text('Baixa')),
                            DropdownMenuItem(value: 'media', child: Text('Média')),
                            DropdownMenuItem(value: 'alta', child: Text('Alta')),
                            DropdownMenuItem(value: 'critica', child: Text('Crítica')),
                          ],
                          onChanged: (v) => setState(() => _filterSeveridade = v),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: anomalias.isEmpty
                      ? const EmptyState(icon: Icons.check_circle_outline, title: 'Nenhuma anomalia encontrada')
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: anomalias.length,
                          itemBuilder: (context, index) {
                            final a = anomalias[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.getCriticalityColor(a.severidade).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.warning_rounded, color: AppColors.getCriticalityColor(a.severidade), size: 20),
                                ),
                                title: Text(AppConstants.anomaliaLabels[a.tipo] ?? a.tipo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (a.descricao != null) Text(a.descricao!, style: const TextStyle(fontSize: 12)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (a.torreCodigo != null) ...[
                                          Icon(MdiIcons.transmissionTower, size: 12, color: AppColors.textMuted),
                                          const SizedBox(width: 4),
                                          Text(a.torreCodigo!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                          const SizedBox(width: 12),
                                        ],
                                        StatusBadge(
                                          status: a.status,
                                          labels: const {'aberta': 'Aberta', 'em_analise': 'Em Análise', 'resolvida': 'Resolvida', 'monitoramento': 'Monitoramento'},
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: CriticalityBadge(criticidade: a.severidade, compact: true),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
