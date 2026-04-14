import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class StatsCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;
  final String? subtitle;
  final VoidCallback? onTap;

  const StatsCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? AppColors.primaryLight;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cardColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: cardColor, size: 22),
                ),
                const Spacer(),
                if (subtitle != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      subtitle!,
                      style: TextStyle(fontSize: 11, color: cardColor, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CriticalityBadge extends StatelessWidget {
  final String criticidade;
  final bool compact;

  const CriticalityBadge({
    super.key,
    required this.criticidade,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.getCriticalityColor(criticidade);
    final labels = {
      'baixa': 'Baixa',
      'media': 'Média',
      'alta': 'Alta',
      'critica': 'Crítica',
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        labels[criticidade] ?? criticidade,
        style: TextStyle(
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String status;
  final Map<String, String> labels;
  final Map<String, Color>? colors;

  const StatusBadge({
    super.key,
    required this.status,
    required this.labels,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final defaultColors = {
      'avaliada': AppColors.success,
      'nao_avaliada': AppColors.textMuted,
      'em_revisao': AppColors.warning,
      'associada': AppColors.success,
      'pendente': AppColors.warning,
      'sem_gps': AppColors.error,
      'manual': AppColors.info,
      'aberta': AppColors.error,
      'em_analise': AppColors.warning,
      'resolvida': AppColors.success,
      'monitoramento': AppColors.info,
    };
    final color = colors?[status] ?? defaultColors[status] ?? AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        labels[status] ?? status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, style: TextStyle(color: AppColors.textMuted), textAlign: TextAlign.center),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
