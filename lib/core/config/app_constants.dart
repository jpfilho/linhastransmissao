class AppConstants {
  static const String appName = 'Inspeção Aérea de Torres';
  static const String appVersion = '1.0.0';

  // Supabase Produção (servidor 10.140.50.10)
  static const String supabaseUrl = 'http://10.140.50.10:54321';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

  // Storage
  static const String storageBucket = 'fotos-inspecao';

  // Configurações de associação
  static const double defaultMaxAssociationRadiusM = 500.0;
  static const double ambiguityThreshold = 0.2; // 20%

  // Qualidade de imagem
  static const double minImageQuality = 0.3;

  // Categorias de foto
  static const List<String> categoriasFoto = [
    'torre_completa',
    'estrutura_metalica',
    'isolador',
    'cabo',
    'vegetacao',
    'acesso',
    'fundacao',
    'outro',
  ];

  // Tipos de anomalia
  static const List<String> tiposAnomalia = [
    'corrosao',
    'vegetacao_proxima',
    'componente_danificado',
    'estrutura_inclinada',
    'fundacao_problema',
    'acesso_comprometido',
    'ocupacao_irregular',
    'queimadas_proximas',
    'outro',
  ];

  // Severidades
  static const List<String> severidades = [
    'baixa',
    'media',
    'alta',
    'critica',
  ];

  // Labels legíveis
  static const Map<String, String> categoriaLabels = {
    'torre_completa': 'Torre Completa',
    'estrutura_metalica': 'Estrutura Metálica',
    'isolador': 'Isolador',
    'cabo': 'Cabo',
    'vegetacao': 'Vegetação',
    'acesso': 'Acesso',
    'fundacao': 'Fundação',
    'outro': 'Outro',
  };

  static const Map<String, String> anomaliaLabels = {
    'corrosao': 'Corrosão',
    'vegetacao_proxima': 'Vegetação Próxima',
    'componente_danificado': 'Componente Danificado',
    'estrutura_inclinada': 'Estrutura Inclinada',
    'fundacao_problema': 'Fundação com Problema',
    'acesso_comprometido': 'Acesso Comprometido',
    'ocupacao_irregular': 'Ocupação Irregular',
    'queimadas_proximas': 'Queimadas Próximas',
    'outro': 'Outro',
  };

  static const Map<String, String> severidadeLabels = {
    'baixa': 'Baixa',
    'media': 'Média',
    'alta': 'Alta',
    'critica': 'Crítica',
  };

  static const Map<String, String> statusAssociacaoLabels = {
    'associada': 'Associada',
    'pendente': 'Pendente',
    'sem_gps': 'Sem GPS',
    'manual': 'Manual',
  };

  static const Map<String, String> statusAvaliacaoLabels = {
    'nao_avaliada': 'Não Avaliada',
    'avaliada': 'Avaliada',
    'em_revisao': 'Em Revisão',
  };
}
