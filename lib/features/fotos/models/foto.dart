import 'dart:typed_data';

class Foto {
  final String id;
  final String? campanhaId;
  final String? linhaId;
  final String? torreId;
  final String? vaoId;
  final String nomeArquivo;
  final String caminhoStorage;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final DateTime? dataHoraCaptura;
  final double? azimute;
  final double? distanciaTorreM;
  final String statusAssociacao;
  final double qualidadeImagem;
  final String statusAvaliacao;
  final String? resultadoPreclassificacao;
  final Map<String, dynamic>? metadadosExif;
  final DateTime? criadoEm;
  final String? torreCodigo;
  final String? linhaNome;
  final String? campanhaNome;
  final String? caminhoLocal;
  final Uint8List? bytesData;
  final String? arquivoEditadoUrl;

  Foto({
    required this.id,
    this.campanhaId,
    this.linhaId,
    this.torreId,
    this.vaoId,
    required this.nomeArquivo,
    required this.caminhoStorage,
    this.latitude,
    this.longitude,
    this.altitude,
    this.dataHoraCaptura,
    this.azimute,
    this.distanciaTorreM,
    this.statusAssociacao = 'pendente',
    this.qualidadeImagem = 0,
    this.statusAvaliacao = 'nao_avaliada',
    this.resultadoPreclassificacao,
    this.metadadosExif,
    this.criadoEm,
    this.torreCodigo,
    this.linhaNome,
    this.campanhaNome,
    this.caminhoLocal,
    this.bytesData,
    this.arquivoEditadoUrl,
  });

  bool get hasGps => latitude != null && longitude != null;

  factory Foto.fromJson(Map<String, dynamic> json) => Foto(
    id: json['id'],
    campanhaId: json['campanha_id'],
    linhaId: json['linha_id'],
    torreId: json['torre_id'],
    vaoId: json['vao_id'],
    nomeArquivo: json['nome_arquivo'] ?? '',
    caminhoStorage: json['caminho_storage'] ?? '',
    latitude: json['latitude']?.toDouble(),
    longitude: json['longitude']?.toDouble(),
    altitude: json['altitude']?.toDouble(),
    dataHoraCaptura: json['data_hora_captura'] != null
        ? DateTime.parse(json['data_hora_captura'])
        : null,
    azimute: json['azimute']?.toDouble(),
    distanciaTorreM: json['distancia_torre_m']?.toDouble(),
    statusAssociacao: json['status_associacao'] ?? 'pendente',
    qualidadeImagem: (json['qualidade_imagem'] ?? 0).toDouble(),
    statusAvaliacao: json['status_avaliacao'] ?? 'nao_avaliada',
    resultadoPreclassificacao: json['resultado_preclassificacao'],
    metadadosExif: json['metadados_exif'],
    criadoEm: json['criado_em'] != null ? DateTime.parse(json['criado_em']) : null,
    torreCodigo: json['torres']?['codigo_torre'] ?? json['torre_codigo'],
    linhaNome: json['linhas']?['nome'] ?? json['linha_nome'],
    campanhaNome: json['campanhas']?['nome'] ?? json['campanha_nome'],
    arquivoEditadoUrl: json['arquivo_editado_url'],
  );

  Map<String, dynamic> toJson() => {
    'campanha_id': campanhaId,
    'linha_id': linhaId,
    'torre_id': torreId,
    'nome_arquivo': nomeArquivo,
    'caminho_storage': caminhoStorage,
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'data_hora_captura': dataHoraCaptura?.toIso8601String(),
    'azimute': azimute,
    'distancia_torre_m': distanciaTorreM,
    'status_associacao': statusAssociacao,
    'qualidade_imagem': qualidadeImagem,
    'status_avaliacao': statusAvaliacao,
    'resultado_preclassificacao': resultadoPreclassificacao,
    'metadados_exif': metadadosExif,
  };
}
