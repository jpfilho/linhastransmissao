class Torre {
  final String id;
  final String? linhaId;
  final String codigoTorre;
  final String? descricao;
  final double latitude;
  final double longitude;
  final double? altitude;
  final String? tipo;
  final String criticidadeAtual;
  final String? observacoes;
  final DateTime? criadoEm;
  final String? linhaNome;
  final int? totalFotos;
  final int? totalAnomalias;

  Torre({
    required this.id,
    this.linhaId,
    required this.codigoTorre,
    this.descricao,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.tipo,
    this.criticidadeAtual = 'baixa',
    this.observacoes,
    this.criadoEm,
    this.linhaNome,
    this.totalFotos,
    this.totalAnomalias,
  });

  factory Torre.fromJson(Map<String, dynamic> json) => Torre(
    id: json['id'],
    linhaId: json['linha_id'],
    codigoTorre: json['codigo_torre'] ?? '',
    descricao: json['descricao'],
    latitude: (json['latitude'] ?? 0).toDouble(),
    longitude: (json['longitude'] ?? 0).toDouble(),
    altitude: json['altitude']?.toDouble(),
    tipo: json['tipo'],
    criticidadeAtual: json['criticidade_atual'] ?? 'baixa',
    observacoes: json['observacoes'],
    criadoEm: json['criado_em'] != null ? DateTime.parse(json['criado_em']) : null,
    linhaNome: json['linhas']?['nome'] ?? json['linha_nome'],
    totalFotos: json['total_fotos'],
    totalAnomalias: json['total_anomalias'],
  );

  Map<String, dynamic> toJson() => {
    'linha_id': linhaId,
    'codigo_torre': codigoTorre,
    'descricao': descricao,
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'tipo': tipo,
    'criticidade_atual': criticidadeAtual,
    'observacoes': observacoes,
  };
}
