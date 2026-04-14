class Avaliacao {
  final String id;
  final String fotoId;
  final String? usuarioId;
  final bool? imagemUtil;
  final String? categoria;
  final String? qualidade;
  final String? observacoes;
  final bool necessitaInspecaoComplementar;
  final DateTime? criadoEm;

  Avaliacao({
    required this.id,
    required this.fotoId,
    this.usuarioId,
    this.imagemUtil,
    this.categoria,
    this.qualidade,
    this.observacoes,
    this.necessitaInspecaoComplementar = false,
    this.criadoEm,
  });

  factory Avaliacao.fromJson(Map<String, dynamic> json) => Avaliacao(
    id: json['id'],
    fotoId: json['foto_id'],
    usuarioId: json['usuario_id'],
    imagemUtil: json['imagem_util'],
    categoria: json['categoria'],
    qualidade: json['qualidade'],
    observacoes: json['observacoes'],
    necessitaInspecaoComplementar: json['necessita_inspecao_complementar'] ?? false,
    criadoEm: json['criado_em'] != null ? DateTime.parse(json['criado_em']) : null,
  );

  Map<String, dynamic> toJson() => {
    'foto_id': fotoId,
    'usuario_id': usuarioId,
    'imagem_util': imagemUtil,
    'categoria': categoria,
    'qualidade': qualidade,
    'observacoes': observacoes,
    'necessita_inspecao_complementar': necessitaInspecaoComplementar,
  };
}
