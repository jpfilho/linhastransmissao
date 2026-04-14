/// Model representing an AI analysis result for a photo.
class AiAnalysis {
  final String id;
  final String fotoId;
  final bool vegetationDetected;
  final double vegetationScore;
  final bool fireSigns;
  final double fireScore;
  final bool structuralIssue;
  final String? anomalyType;
  final double severityScore;
  final double confidence;
  final double qualityBlur;
  final double qualityExposure;
  final String? summary;
  final String modelVersion;
  final DateTime processedAt;

  AiAnalysis({
    required this.id,
    required this.fotoId,
    this.vegetationDetected = false,
    this.vegetationScore = 0,
    this.fireSigns = false,
    this.fireScore = 0,
    this.structuralIssue = false,
    this.anomalyType,
    this.severityScore = 0,
    this.confidence = 0,
    this.qualityBlur = 0,
    this.qualityExposure = 0,
    this.summary,
    this.modelVersion = 'v1.0',
    required this.processedAt,
  });

  factory AiAnalysis.fromJson(Map<String, dynamic> json) => AiAnalysis(
    id: json['id'],
    fotoId: json['foto_id'],
    vegetationDetected: json['vegetation_detected'] ?? false,
    vegetationScore: (json['vegetation_score'] ?? 0).toDouble(),
    fireSigns: json['fire_signs'] ?? false,
    fireScore: (json['fire_score'] ?? 0).toDouble(),
    structuralIssue: json['structural_issue'] ?? false,
    anomalyType: json['anomaly_type'],
    severityScore: (json['severity_score'] ?? 0).toDouble(),
    confidence: (json['confidence'] ?? 0).toDouble(),
    qualityBlur: (json['quality_blur'] ?? 0).toDouble(),
    qualityExposure: (json['quality_exposure'] ?? 0).toDouble(),
    summary: json['summary'],
    modelVersion: json['model_version'] ?? 'v1.0',
    processedAt: DateTime.parse(json['processed_at']),
  );

  /// Severity level label
  String get severityLabel {
    if (severityScore >= 75) return 'Crítico';
    if (severityScore >= 50) return 'Alto';
    if (severityScore >= 20) return 'Médio';
    if (severityScore > 0) return 'Baixo';
    return 'Normal';
  }

  /// List of detected issues as tags
  List<String> get detectedTags {
    final tags = <String>[];
    if (vegetationDetected) tags.add('Vegetação');
    if (fireSigns) tags.add('Fogo/Queimada');
    if (structuralIssue) tags.add('Dano Estrutural');
    if (anomalyType != null) tags.add(_anomalyLabel(anomalyType!));
    return tags;
  }

  String _anomalyLabel(String type) {
    const labels = {
      'corrosion': 'Corrosão',
      'vegetation_encroachment': 'Vegetação',
      'insulator_damage': 'Isolador Danificado',
      'conductor_damage': 'Condutor Danificado',
      'foundation_issue': 'Fundação',
      'bird_nest': 'Ninho de Ave',
      'missing_hardware': 'Ferragem Ausente',
      'burn_marks': 'Marcas de Queimada',
    };
    return labels[type] ?? type;
  }
}

/// Model for tower risk scoring.
class TowerRisk {
  final String id;
  final String torreId;
  final double riskScore;
  final String priorityLevel;
  final double aiSeverityAvg;
  final double vegetationRisk;
  final double fireRisk;
  final double lightningRisk;
  final int historicalAnomalies;
  final int? daysSinceInspection;
  final String trend;
  final DateTime lastCalculated;

  TowerRisk({
    required this.id,
    required this.torreId,
    this.riskScore = 0,
    this.priorityLevel = 'LOW',
    this.aiSeverityAvg = 0,
    this.vegetationRisk = 0,
    this.fireRisk = 0,
    this.lightningRisk = 0,
    this.historicalAnomalies = 0,
    this.daysSinceInspection,
    this.trend = 'stable',
    required this.lastCalculated,
  });

  factory TowerRisk.fromJson(Map<String, dynamic> json) => TowerRisk(
    id: json['id'],
    torreId: json['torre_id'],
    riskScore: (json['risk_score'] ?? 0).toDouble(),
    priorityLevel: json['priority_level'] ?? 'LOW',
    aiSeverityAvg: (json['ai_severity_avg'] ?? 0).toDouble(),
    vegetationRisk: (json['vegetation_risk'] ?? 0).toDouble(),
    fireRisk: (json['fire_risk'] ?? 0).toDouble(),
    lightningRisk: (json['lightning_risk'] ?? 0).toDouble(),
    historicalAnomalies: json['historical_anomalies'] ?? 0,
    daysSinceInspection: json['days_since_inspection'],
    trend: json['trend'] ?? 'stable',
    lastCalculated: DateTime.parse(json['last_calculated']),
  );

  String get priorityLabel {
    const labels = {'LOW': 'Baixo', 'MEDIUM': 'Médio', 'HIGH': 'Alto', 'CRITICAL': 'Crítico'};
    return labels[priorityLevel] ?? priorityLevel;
  }

  String get trendLabel {
    const labels = {'improving': '↗ Melhorando', 'stable': '→ Estável', 'worsening': '↘ Piorando'};
    return labels[trend] ?? trend;
  }
}

/// Model for AI-generated reports.
class AiReport {
  final String id;
  final String? fotoId;
  final String? torreId;
  final String reportType;
  final String content;
  final String? suggestedAction;
  final String? riskInterpretation;
  final String modelUsed;
  final DateTime generatedAt;

  AiReport({
    required this.id,
    this.fotoId,
    this.torreId,
    this.reportType = 'photo_analysis',
    required this.content,
    this.suggestedAction,
    this.riskInterpretation,
    this.modelUsed = 'gpt-4o-mini',
    required this.generatedAt,
  });

  factory AiReport.fromJson(Map<String, dynamic> json) => AiReport(
    id: json['id'],
    fotoId: json['foto_id'],
    torreId: json['torre_id'],
    reportType: json['report_type'] ?? 'photo_analysis',
    content: json['content'],
    suggestedAction: json['suggested_action'],
    riskInterpretation: json['risk_interpretation'],
    modelUsed: json['model_used'] ?? 'gpt-4o-mini',
    generatedAt: DateTime.parse(json['generated_at']),
  );
}
