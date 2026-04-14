class Anomalia {
  final String id;
  final String? fotoId;
  final String? torreId;
  final String tipo;
  final String severidade;
  final String? descricao;
  final String? recomendacao;
  final String status;
  final String? criadoPor;
  final DateTime? criadoEm;
  final String? torreCodigo;
  final String? fotoNome;

  Anomalia({
    required this.id,
    this.fotoId,
    this.torreId,
    required this.tipo,
    this.severidade = 'media',
    this.descricao,
    this.recomendacao,
    this.status = 'aberta',
    this.criadoPor,
    this.criadoEm,
    this.torreCodigo,
    this.fotoNome,
  });

  factory Anomalia.fromJson(Map<String, dynamic> json) => Anomalia(
    id: json['id'],
    fotoId: json['foto_id'],
    torreId: json['torre_id'],
    tipo: json['tipo'] ?? 'outro',
    severidade: json['severidade'] ?? 'media',
    descricao: json['descricao'],
    recomendacao: json['recomendacao'],
    status: json['status'] ?? 'aberta',
    criadoPor: json['criado_por'],
    criadoEm: json['criado_em'] != null ? DateTime.parse(json['criado_em']) : null,
    torreCodigo: json['torres']?['codigo_torre'] ?? json['torre_codigo'],
    fotoNome: json['fotos']?['nome_arquivo'] ?? json['foto_nome'],
  );

  Map<String, dynamic> toJson() => {
    'foto_id': fotoId,
    'torre_id': torreId,
    'tipo': tipo,
    'severidade': severidade,
    'descricao': descricao,
    'recomendacao': recomendacao,
    'status': status,
  };
}
