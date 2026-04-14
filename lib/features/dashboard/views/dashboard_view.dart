import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/services/ai_service.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../../core/config/app_constants.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late Future<Map<String, dynamic>> _statsFuture;
  late Future<Map<String, int>> _anomaliasFuture;
  late Future<Map<String, int>> _criticidadeFuture;
  late Future<Map<String, int>> _fotosCampanhaFuture;
  late Future<Map<String, dynamic>> _aiStatsFuture;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _loadAll() {
    _statsFuture = SupabaseService.getDashboardStats();
    _anomaliasFuture = SupabaseService.getAnomaliasPorTipo();
    _criticidadeFuture = SupabaseService.getCriticidadeDistribuicao();
    _fotosCampanhaFuture = SupabaseService.getFotosPorCampanha();
    _aiStatsFuture = AiService.getAiStats();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        leading: isWide ? null : Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => setState(() => _loadAll()),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snapshot.data ?? {};
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text('Inspeção Aérea de Torres', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('Visão geral do sistema', style: TextStyle(color: AppColors.textSecondary)),
                    if (snapshot.connectionState == ConnectionState.waiting) ...[
                      const SizedBox(width: 8),
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                    if (snapshot.hasData) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Supabase ✓', style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w600)),
                      ),
                    ],
                    if (snapshot.hasError) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Erro ✗', style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),

                // Stats Cards
                _buildStatsGrid(stats, isWide),

                const SizedBox(height: 16),

                // AI Stats
                _buildAiStatsSection(isWide),

                const SizedBox(height: 32),

                // Charts row
                if (isWide) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildAnomaliasPorTipoChart()),
                      const SizedBox(width: 20),
                      Expanded(child: _buildCriticidadeChart()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildFotosPorCampanhaChart()),
                      const SizedBox(width: 20),
                      Expanded(child: _buildQuickActions()),
                    ],
                  ),
                ] else ...[
                  _buildAnomaliasPorTipoChart(),
                  const SizedBox(height: 20),
                  _buildCriticidadeChart(),
                  const SizedBox(height: 20),
                  _buildFotosPorCampanhaChart(),
                  const SizedBox(height: 20),
                  _buildQuickActions(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsGrid(Map<String, dynamic> stats, bool isWide) {
    final cards = [
      StatsCard(title: 'Linhas de Transmissão', value: '${stats['total_linhas'] ?? 0}', icon: Icons.flash_on_rounded, color: AppColors.primary),
      StatsCard(title: 'Torres', value: '${stats['total_torres'] ?? 0}', icon: MdiIcons.transmissionTower, color: AppColors.info),
      StatsCard(title: 'Fotos', value: '${stats['total_fotos'] ?? 0}', icon: Icons.photo_camera_rounded, color: AppColors.success),
      StatsCard(title: 'Fotos sem Associação', value: '${stats['fotos_sem_associacao'] ?? 0}', icon: Icons.link_off, color: AppColors.warning, subtitle: stats['fotos_sem_associacao'] != null && stats['fotos_sem_associacao'] > 0 ? 'PENDENTE' : null),
      StatsCard(title: 'Fotos sem Avaliação', value: '${stats['fotos_sem_avaliacao'] ?? 0}', icon: Icons.rate_review_rounded, color: AppColors.error, subtitle: stats['fotos_sem_avaliacao'] != null && stats['fotos_sem_avaliacao'] > 0 ? 'A AVALIAR' : null),
      StatsCard(title: 'Torres Críticas', value: '${stats['torres_criticas'] ?? 0}', icon: Icons.warning_rounded, color: AppColors.error),
      StatsCard(title: 'Anomalias Abertas', value: '${stats['anomalias_abertas'] ?? 0}', icon: Icons.report_problem_rounded, color: AppColors.warning),
      StatsCard(title: 'Campanhas Ativas', value: '${stats['campanhas_ativas'] ?? 0}', icon: Icons.calendar_today_rounded, color: AppColors.primary),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isWide ? 4 : 2,
      childAspectRatio: isWide ? 2.2 : 1.8,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: cards,
    );
  }

  Widget _buildAnomaliasPorTipoChart() {
    return FutureBuilder<Map<String, int>>(
      future: _anomaliasFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? {};
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
              const Text('Anomalias por Tipo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              data.isEmpty
                  ? const SizedBox(height: 30, child: Center(child: Text('Sem dados', style: TextStyle(color: AppColors.textMuted))))
                  : SizedBox(
                      height: 200,
                      child: PieChart(PieChartData(
                        sections: data.entries.map((e) {
                          final label = AppConstants.anomaliaLabels[e.key] ?? e.key;
                          final anomaliaColors = <String, Color>{
                            'corrosao': const Color(0xFFE53E3E),
                            'isolador': const Color(0xFF3182CE),
                            'vegetacao': const Color(0xFF38A169),
                            'estrutural': const Color(0xFFED8936),
                            'condutor': const Color(0xFFECC94B),
                            'ferragem': const Color(0xFF805AD5),
                          };
                          return PieChartSectionData(
                            value: e.value.toDouble(),
                            title: '${e.value}',
                            radius: 60,
                            titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                            color: anomaliaColors[e.key] ?? AppColors.info,
                            badgeWidget: Text(label, style: const TextStyle(fontSize: 9)),
                            badgePositionPercentageOffset: 1.3,
                          );
                        }).toList(),
                        centerSpaceRadius: 30,
                      )),
                    ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCriticidadeChart() {
    return FutureBuilder<Map<String, int>>(
      future: _criticidadeFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? {};
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
              const Text('Criticidade das Torres', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: BarChart(BarChartData(
                  barGroups: [
                    _bar(0, (data['baixa'] ?? 0).toDouble(), AppColors.success),
                    _bar(1, (data['media'] ?? 0).toDouble(), AppColors.warning),
                    _bar(2, (data['alta'] ?? 0).toDouble(), AppColors.error),
                    _bar(3, (data['critica'] ?? 0).toDouble(), const Color(0xFFDC2626)),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, m) {
                          const labels = ['Baixa', 'Média', 'Alta', 'Crítica'];
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(labels[v.toInt()], style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                )),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFotosPorCampanhaChart() {
    return FutureBuilder<Map<String, int>>(
      future: _fotosCampanhaFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? {};
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
              const Text('Fotos por Campanha', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              data.isEmpty
                  ? const SizedBox(height: 30, child: Center(child: Text('Sem campanhas', style: TextStyle(color: AppColors.textMuted))))
                  : SizedBox(
                      height: 200,
                      child: BarChart(BarChartData(
                        barGroups: data.entries.toList().asMap().entries.map((entry) =>
                          _bar(entry.key, entry.value.value.toDouble(), AppColors.info),
                        ).toList(),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, m) {
                                final names = data.keys.toList();
                                final idx = v.toInt();
                                if (idx >= names.length) return const SizedBox();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(names[idx], style: const TextStyle(fontSize: 9, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(show: false),
                      )),
                    ),
            ],
          ),
        );
      },
    );
  }

  BarChartGroupData _bar(int x, double y, Color color) {
    return BarChartGroupData(x: x, barRods: [
      BarChartRodData(toY: y, color: color, width: 28, borderRadius: BorderRadius.circular(6)),
    ]);
  }

  Widget _buildQuickActions() {
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
          const Text('Ações Rápidas', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _actionTile(Icons.add_photo_alternate, 'Importar KMZ', '/importacao-kmz', AppColors.primary),
          _actionTile(Icons.photo_library, 'Importar Fotos', '/importacao-fotos', AppColors.info),
          _actionTile(Icons.map_rounded, 'Mapa de Inspeção', '/mapa', AppColors.success),
          _actionTile(Icons.rate_review, 'Fila de Revisão', '/avaliacoes', AppColors.warning),
        ],
      ),
    );
  }

  Widget _actionTile(IconData icon, String title, String route, Color color) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
      onTap: () => context.go(route),
    );
  }

  Widget _buildAiStatsSection(bool isWide) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _aiStatsFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? {};
        final totalAnalyzed = data['total_analyzed'] ?? 0;
        if (totalAnalyzed == 0 && !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.psychology, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text('Inteligência Artificial', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$totalAnalyzed analisadas', style: const TextStyle(fontSize: 11, color: AppColors.primary)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: isWide ? 4 : 2,
                childAspectRatio: isWide ? 2.5 : 2.0,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  StatsCard(title: 'Vegetação', value: '${data['vegetation_alerts'] ?? 0}', icon: Icons.park, color: Colors.green),
                  StatsCard(title: 'Incêndio', value: '${data['fire_alerts'] ?? 0}', icon: Icons.local_fire_department, color: Colors.deepOrange),
                  StatsCard(title: 'Estrutural', value: '${data['structural_alerts'] ?? 0}', icon: Icons.construction, color: Colors.orange),
                  StatsCard(title: 'Torres Críticas', value: '${data['critical_towers'] ?? 0}', icon: Icons.shield, color: AppColors.error),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

