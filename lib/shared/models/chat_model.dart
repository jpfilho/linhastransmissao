class AppUsuario {
  final int id;
  final String nome;
  final String role;
  final String? avatarUrl;

  AppUsuario({
    required this.id,
    required this.nome,
    required this.role,
    this.avatarUrl,
  });

  factory AppUsuario.fromJson(Map<String, dynamic> json) {
    return AppUsuario(
      id: json['id'] as int,
      nome: json['nome'] as String,
      role: json['role'] as String? ?? 'user',
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class ChatMensagem {
  final int id;
  final String torreId;
  final int usuarioId;
  final String mensagem;
  final DateTime createdAt;
  
  // Media / Attachment Fields
  final String? tipoAnexo;
  final String? urlAnexo;
  final double? geoLat;
  final double? geoLon;
  final Map<String, dynamic>? metadata;

  // Added optionally for joining UI rendering purposes
  AppUsuario? usuario;

  ChatMensagem({
    required this.id,
    required this.torreId,
    required this.usuarioId,
    required this.mensagem,
    required this.createdAt,
    this.tipoAnexo,
    this.urlAnexo,
    this.geoLat,
    this.geoLon,
    this.metadata,
    this.usuario,
  });

  factory ChatMensagem.fromJson(Map<String, dynamic> json) {
    return ChatMensagem(
      id: json['id'] as int,
      torreId: json['torre_id'] as String,
      usuarioId: json['usuario_id'] as int,
      mensagem: json['mensagem'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      tipoAnexo: json['tipo_anexo'] as String?,
      urlAnexo: json['url_anexo'] as String?,
      geoLat: (json['geo_lat'] as num?)?.toDouble(),
      geoLon: (json['geo_lon'] as num?)?.toDouble(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      usuario: json['app_usuarios'] != null 
          ? AppUsuario.fromJson(json['app_usuarios'] as Map<String, dynamic>) 
          : null,
    );
  }
}
