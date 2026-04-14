class Linha {
  final String id;
  final String nome;
  final String? codigo;
  final String? regional;
  final String? tensao;
  final double? extensaoKm;
  final String? observacoes;
  final Map<String, dynamic>? geometriaJson;
  final DateTime? criadoEm;
  final int? totalTorres;
  final int? totalFotos;

  Linha({
    required this.id,
    required this.nome,
    this.codigo,
    this.regional,
    this.tensao,
    this.extensaoKm,
    this.observacoes,
    this.geometriaJson,
    this.criadoEm,
    this.totalTorres,
    this.totalFotos,
  });

  factory Linha.fromJson(Map<String, dynamic> json) => Linha(
    id: json['id'],
    nome: json['nome'],
    codigo: json['codigo'],
    regional: json['regional'],
    tensao: json['tensao'],
    extensaoKm: json['extensao_km']?.toDouble(),
    observacoes: json['observacoes'],
    geometriaJson: json['geometria_json'],
    criadoEm: json['criado_em'] != null ? DateTime.parse(json['criado_em']) : null,
    totalTorres: json['total_torres'],
    totalFotos: json['total_fotos'],
  );

  Map<String, dynamic> toJson() => {
    'nome': nome,
    'codigo': codigo,
    'regional': regional,
    'tensao': tensao,
    'extensao_km': extensaoKm,
    'observacoes': observacoes,
    'geometria_json': geometriaJson,
  };
}
