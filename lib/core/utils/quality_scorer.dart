class QualityScorer {
  /// Calcula score de qualidade da imagem baseado em metadados
  /// Retorna valor entre 0.0 e 1.0
  static double calculateScore({
    bool hasGps = false,
    int? imageWidth,
    int? imageHeight,
    double? altitude,
    bool hasDateTime = false,
    bool hasAzimuth = false,
  }) {
    double score = 0.0;
    int factors = 0;

    // GPS (peso alto)
    factors += 3;
    if (hasGps) score += 3.0;

    // Resolução
    factors += 2;
    if (imageWidth != null && imageHeight != null) {
      final pixels = imageWidth * imageHeight;
      if (pixels >= 12000000) {
        score += 2.0; // 12MP+
      } else if (pixels >= 8000000) {
        score += 1.5;
      } else if (pixels >= 4000000) {
        score += 1.0;
      } else if (pixels >= 2000000) {
        score += 0.5;
      }
    }

    // Data e hora
    factors += 1;
    if (hasDateTime) score += 1.0;

    // Altitude (indica foto aérea)
    factors += 1;
    if (altitude != null && altitude > 10) score += 1.0;

    // Azimute
    factors += 1;
    if (hasAzimuth) score += 1.0;

    return factors > 0 ? (score / factors).clamp(0.0, 1.0) : 0.0;
  }

  static String qualityLabel(double score) {
    if (score >= 0.7) return 'Boa';
    if (score >= 0.4) return 'Média';
    return 'Ruim';
  }
}
