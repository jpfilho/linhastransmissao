import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/dashboard/views/dashboard_view.dart';
import '../../features/mapa_inspecao/views/inspection_map_view.dart';
import '../../features/importacao_kmz/views/kmz_import_view.dart';
import '../../features/importacao_fotos/views/photo_import_view.dart';
import '../../features/torres/views/torre_list_view.dart';
import '../../features/torres/views/torre_detail_view.dart';
import '../../features/fotos/views/foto_list_view.dart';
import '../../features/fotos/views/foto_detail_view.dart';
import '../../features/avaliacoes/views/avaliacao_view.dart';
import '../../features/anomalias/views/anomalia_list_view.dart';
import '../../features/anomalias/views/anomalia_form_view.dart';
import '../../features/comparacao_temporal/views/temporal_comparison_view.dart';
import '../../features/analise_ia/views/batch_analysis_view.dart';
import '../../features/supressao/views/supressao_list_view.dart';
import '../../features/supressao/views/supressao_import_view.dart';
import '../../features/supressao/views/supressao_analysis_view.dart';
import '../../features/campanhas/views/campanha_viewer_view.dart';
import '../../shared/widgets/app_drawer.dart';

class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _isSidebarCollapsed = false;

  void _toggleSidebar() {
    setState(() {
      _isSidebarCollapsed = !_isSidebarCollapsed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: _isSidebarCollapsed ? 72 : 260,
              child: AppDrawer(
                isCollapsed: _isSidebarCollapsed,
                onToggleCollapse: _toggleSidebar,
              ),
            ),
            Expanded(child: widget.child),
          ],
        ),
      );
    }

    return Scaffold(
      drawer: const AppDrawer(),
      body: widget.child,
    );
  }
}

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardView(),
        ),
        GoRoute(
          path: '/mapa',
          builder: (context, state) => const InspectionMapView(),
        ),
        GoRoute(
          path: '/importar-kmz',
          builder: (context, state) => const KmzImportView(),
        ),
        GoRoute(
          path: '/importar-fotos',
          builder: (context, state) => const PhotoImportView(),
        ),
        GoRoute(
          path: '/linhas',
          builder: (context, state) => const TorreListView(), // Tower list includes line filter
        ),
        GoRoute(
          path: '/torres',
          builder: (context, state) => const TorreListView(),
        ),
        GoRoute(
          path: '/torres/:id',
          builder: (context, state) => TorreDetailView(torreId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/fotos',
          builder: (context, state) => const FotoListView(),
        ),
        GoRoute(
          path: '/fotos/:id',
          builder: (context, state) => FotoDetailView(fotoId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/campanhas',
          builder: (context, state) => const CampanhaViewerView(),
        ),
        GoRoute(
          path: '/avaliacoes',
          builder: (context, state) => const AvaliacaoView(),
        ),
        GoRoute(
          path: '/anomalias',
          builder: (context, state) => const AnomaliaListView(),
        ),
        GoRoute(
          path: '/anomalias/nova',
          builder: (context, state) => const AnomaliaFormView(),
        ),
        GoRoute(
          path: '/fila-revisao',
          builder: (context, state) => const AvaliacaoView(), // Review queue is part of evaluations
        ),
        GoRoute(
          path: '/comparacao',
          builder: (context, state) => const TemporalComparisonView(),
        ),
        GoRoute(
          path: '/analise-ia',
          builder: (context, state) => const BatchAnalysisView(),
        ),
        GoRoute(
          path: '/supressao',
          builder: (context, state) => const SupressaoListView(),
        ),
        GoRoute(
          path: '/importar-supressao',
          builder: (context, state) => const SupressaoImportView(),
        ),
        GoRoute(
          path: '/analise-supressao',
          builder: (context, state) => const SupressaoAnalysisView(),
        ),
      ],
    ),
  ],
);
