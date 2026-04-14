import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

class AppDrawer extends StatelessWidget {
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;

  const AppDrawer({
    super.key,
    this.isCollapsed = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final currentRoute = GoRouterState.of(context).uri.toString();

    return Material(
      color: AppColors.bgSurface,
      elevation: 4,
      child: Container(
        color: AppColors.bgSurface,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildNavItem(context, '/', Icons.dashboard_rounded, 'Dashboard', currentRoute),
                  _buildNavItem(context, '/mapa', Icons.map_rounded, 'Mapa de Inspeção', currentRoute),
                  _DrawerDivider(label: 'IMPORTAÇÃO', isCollapsed: isCollapsed),
                  _buildNavItem(context, '/importar-kmz', Icons.upload_file_rounded, 'Importar KMZ', currentRoute),
                  _buildNavItem(context, '/importar-fotos', Icons.photo_library_rounded, 'Importar Fotos', currentRoute),
                  _DrawerDivider(label: 'GESTÃO', isCollapsed: isCollapsed),
                  _buildNavItem(context, '/linhas', Icons.power_rounded, 'Linhas', currentRoute),
                  _buildNavItem(context, '/torres', MdiIcons.transmissionTower, 'Torres', currentRoute),
                  _buildNavItem(context, '/fotos', Icons.photo_camera_rounded, 'Fotos', currentRoute),
                  _buildNavItem(context, '/campanhas', Icons.campaign_rounded, 'Campanhas', currentRoute),
                  _DrawerDivider(label: 'AVALIAÇÃO', isCollapsed: isCollapsed),
                  _buildNavItem(context, '/avaliacoes', Icons.rate_review_rounded, 'Avaliações', currentRoute),
                  _buildNavItem(context, '/anomalias', Icons.warning_rounded, 'Anomalias', currentRoute),
                  _buildNavItem(context, '/fila-revisao', Icons.playlist_add_check_rounded, 'Fila de Revisão', currentRoute),
                  _DrawerDivider(label: 'ANÁLISE', isCollapsed: isCollapsed),
                  _buildNavItem(context, '/comparacao', Icons.compare_rounded, 'Comparação Temporal', currentRoute),
                  _buildNavItem(context, '/analise-ia', Icons.auto_awesome, 'Análise IA em Lote', currentRoute),
                  _DrawerDivider(label: 'SUPRESSÃO DE VEGETAÇÃO', isCollapsed: isCollapsed),
                  _buildNavItem(context, '/supressao', Icons.grass, 'Mapeamento Roço', currentRoute),
                  _buildNavItem(context, '/importar-supressao', Icons.upload_file, 'Importar Planilha', currentRoute),
                  _buildNavItem(context, '/analise-supressao', Icons.auto_awesome, 'IA + Mapeamento', currentRoute),
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(isCollapsed ? 12 : 20, 48, isCollapsed ? 12 : 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryLight.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: isCollapsed ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: onToggleCollapse,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(MdiIcons.transmissionTower, color: Colors.white, size: isCollapsed ? 24 : 28),
                ),
              ),
              if (!isCollapsed && onToggleCollapse != null)
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                  onPressed: onToggleCollapse,
                  tooltip: 'Recolher menu',
                ),
            ],
          ),
          if (!isCollapsed) ...[
            const SizedBox(height: 12),
            const Text(
              'Inspeção Aérea',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text(
              'Torres de Transmissão',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    String route,
    IconData icon,
    String label,
    String currentRoute,
  ) {
    final isSelected = currentRoute == route ||
        (route != '/' && currentRoute.startsWith(route));

    return Tooltip(
      message: isCollapsed ? label : '',
      preferBelow: false,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: isCollapsed ? 12 : 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isSelected ? AppColors.primaryLight.withValues(alpha: 0.15) : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (Navigator.of(context).canPop() && !isCollapsed) {
              Navigator.pop(context);
            }
            context.go(route);
          },
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: isCollapsed ? 0 : 16),
            child: Row(
              mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? AppColors.primaryLight : AppColors.textSecondary,
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (isCollapsed) {
       return const Padding(
         padding: EdgeInsets.symmetric(vertical: 16),
         child: Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
       );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      child: const Text(
        'v1.0.0 • Modo Demo',
        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _DrawerDivider extends StatelessWidget {
  final String label;
  final bool isCollapsed;
  const _DrawerDivider({required this.label, this.isCollapsed = false});

  @override
  Widget build(BuildContext context) {
    if (isCollapsed) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Divider(color: AppColors.border, height: 1, indent: 12, endIndent: 12),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
