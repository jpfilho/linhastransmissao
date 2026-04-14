import 'package:flutter/material.dart';

class AppColors {
  // Primary - Deep industrial blue
  static const Color primary = Color(0xFF1A365D);
  static const Color primaryLight = Color(0xFF2B6CB0);
  static const Color primaryDark = Color(0xFF0F2440);

  // Accent - Electric amber/orange (energy sector)
  static const Color accent = Color(0xFFED8936);
  static const Color accentLight = Color(0xFFF6AD55);
  static const Color accentDark = Color(0xFFDD6B20);

  // Status colors
  static const Color success = Color(0xFF38A169);
  static const Color warning = Color(0xFFECC94B);
  static const Color error = Color(0xFFE53E3E);
  static const Color info = Color(0xFF3182CE);

  // Criticality
  static const Color critBaixa = Color(0xFF38A169);
  static const Color critMedia = Color(0xFFECC94B);
  static const Color critAlta = Color(0xFFED8936);
  static const Color critCritica = Color(0xFFE53E3E);

  // Background
  static const Color bgDark = Color(0xFF0F1724);
  static const Color bgCard = Color(0xFF1A2332);
  static const Color bgSurface = Color(0xFF1E293B);
  static const Color bgElevated = Color(0xFF243447);

  // Text
  static const Color textPrimary = Color(0xFFE2E8F0);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Border
  static const Color border = Color(0xFF334155);
  static const Color borderLight = Color(0xFF475569);

  static Color getCriticalityColor(String? criticidade) {
    switch (criticidade) {
      case 'critica':
        return critCritica;
      case 'alta':
        return critAlta;
      case 'media':
        return critMedia;
      case 'baixa':
      default:
        return critBaixa;
    }
  }

  static Color getStatusColor(String? status) {
    switch (status) {
      case 'avaliada':
        return success;
      case 'em_revisao':
        return warning;
      case 'nao_avaliada':
      default:
        return textMuted;
    }
  }

  static Color getColorForLinha(String? identifier) {
    if (identifier == null || identifier.isEmpty) return textMuted;
    final colors = [
      const Color(0xFFE53E3E), // Red
      const Color(0xFF3182CE), // Blue
      const Color(0xFF38A169), // Green
      const Color(0xFFDD6B20), // Orange
      const Color(0xFF805AD5), // Purple
      const Color(0xFF319795), // Teal
      const Color(0xFFD53F8C), // Pink
      const Color(0xFF4C51BF), // Indigo
      const Color(0xFF975A16), // Brown
      const Color(0xFF00B5D8), // Cyan
    ];
    final hash = identifier.hashCode.abs();
    return colors[hash % colors.length];
  }
}
