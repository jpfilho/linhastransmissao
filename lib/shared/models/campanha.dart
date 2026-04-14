class Campanha {
  final String id;
  final String nome;
  final String? descricao;
  final DateTime? dataInicio;
  final DateTime? dataFim;
  final String status;
  final String? criadoPor;
  final DateTime? criadoEm;
  final int? totalFotos;

  Campanha({
    required this.id,
    required this.nome,
    this.descricao,
    this.dataInicio,
    this.dataFim,
    this.status = 'planejada',
    this.criadoPor,
    this.criadoEm,
    this.totalFotos,
  });

  factory Campanha.fromJson(Map<String, dynamic> json) => Campanha(
    id: json['id'],
    nome: json['nome'],
    descricao: json['descricao'],
    dataInicio: json['data_inicio'] != null ? DateTime.parse(json['data_inicio']) : null,
    dataFim: json['data_fim'] != null ? DateTime.parse(json['data_fim']) : null,
    status: json['status'] ?? 'planejada',
    criadoPor: json['criado_por'],
    criadoEm: json['criado_em'] != null ? DateTime.parse(json['criado_em']) : null,
    totalFotos: json['total_fotos'],
  );

  Map<String, dynamic> toJson() => {
    'nome': nome,
    'descricao': descricao,
    'data_inicio': dataInicio?.toIso8601String().split('T')[0],
    'data_fim': dataFim?.toIso8601String().split('T')[0],
    'status': status,
  };

  String get statusLabel {
    switch (status) {
      case 'planejada': return 'Planejada';
      case 'em_andamento': return 'Em Andamento';
      case 'concluida': return 'Concluída';
      case 'cancelada': return 'Cancelada';
      default: return status;
    }
  }
}
