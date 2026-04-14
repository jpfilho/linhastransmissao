class MapeamentoSupressao {
  final String id;
  final String? torreId;
  final String? linhaId;
  final String estCodigo;
  final double? vaoFrenteM;
  final double? larguraM;
  
  // Mapeamento
  final double? mapMecExtensao;
  final double? mapMecLargura;
  final double? mapManExtensao;
  final double? mapManLargura;
  
  // Execução
  final double? execMecExtensao;
  final double? execMecLargura;
  final double? execManExtensao;
  final double? execManLargura;
  
  // Status
  final DateTime? dataConclusao;
  final bool rocoConcluido;
  final String? atende;
  
  // GGT
  final int? numeracaoGgt;
  final String? mapeamentoGgt;
  final String? codigoGgtExecucao;
  
  // Descrição
  final String? descricaoServico;
  final String? prioridade;
  final String? campanhaRoco;
  final String? nomeLinhaPlanilha;
  
  // Áreas
  final double? areaManual;
  final double? areaMecanizado;
  final double? conferenciaVao;
  
  // Torre info (from join)
  final String? codigoTorre;
  final String? linhaNome;

  MapeamentoSupressao({
    required this.id,
    this.torreId,
    this.linhaId,
    required this.estCodigo,
    this.vaoFrenteM,
    this.larguraM,
    this.mapMecExtensao,
    this.mapMecLargura,
    this.mapManExtensao,
    this.mapManLargura,
    this.execMecExtensao,
    this.execMecLargura,
    this.execManExtensao,
    this.execManLargura,
    this.dataConclusao,
    this.rocoConcluido = false,
    this.atende,
    this.numeracaoGgt,
    this.mapeamentoGgt,
    this.codigoGgtExecucao,
    this.descricaoServico,
    this.prioridade,
    this.campanhaRoco,
    this.nomeLinhaPlanilha,
    this.areaManual,
    this.areaMecanizado,
    this.conferenciaVao,
    this.codigoTorre,
    this.linhaNome,
  });

  factory MapeamentoSupressao.fromJson(Map<String, dynamic> json) => MapeamentoSupressao(
    id: json['id'],
    torreId: json['torre_id'],
    linhaId: json['linha_id'],
    estCodigo: json['est_codigo'] ?? '',
    vaoFrenteM: json['vao_frente_m']?.toDouble(),
    larguraM: json['largura_m']?.toDouble(),
    mapMecExtensao: json['map_mec_extensao']?.toDouble(),
    mapMecLargura: json['map_mec_largura']?.toDouble(),
    mapManExtensao: json['map_man_extensao']?.toDouble(),
    mapManLargura: json['map_man_largura']?.toDouble(),
    execMecExtensao: json['exec_mec_extensao']?.toDouble(),
    execMecLargura: json['exec_mec_largura']?.toDouble(),
    execManExtensao: json['exec_man_extensao']?.toDouble(),
    execManLargura: json['exec_man_largura']?.toDouble(),
    dataConclusao: json['data_conclusao'] != null ? DateTime.tryParse(json['data_conclusao']) : null,
    rocoConcluido: json['roco_concluido'] ?? false,
    atende: json['atende'],
    numeracaoGgt: json['numeracao_ggt'],
    mapeamentoGgt: json['mapeamento_ggt'],
    codigoGgtExecucao: json['codigo_ggt_execucao'],
    descricaoServico: json['descricao_servico'],
    prioridade: json['prioridade'],
    campanhaRoco: json['campanha_roco'],
    nomeLinhaPlanilha: json['nome_linha_planilha'],
    areaManual: json['area_manual']?.toDouble(),
    areaMecanizado: json['area_mecanizado']?.toDouble(),
    conferenciaVao: json['conferencia_vao']?.toDouble(),
    codigoTorre: json['torres']?['codigo_torre'],
    linhaNome: json['linhas']?['nome'],
  );

  /// Whether this span has any mapping planned
  bool get hasMapeamento => 
      (mapMecExtensao ?? 0) > 0 || (mapManExtensao ?? 0) > 0;
  
  /// Whether this span has any execution done
  bool get hasExecucao => 
      (execMecExtensao ?? 0) > 0 || (execManExtensao ?? 0) > 0;
  
  /// Priority color
  String get prioridadeLabel {
    switch (prioridade) {
      case 'P1': return '🔴 P1 - Crítica';
      case 'P2': return '🟡 P2 - Alta';
      case 'P3': return '🟢 P3 - Normal';
      default: return prioridade ?? '—';
    }
  }
}
