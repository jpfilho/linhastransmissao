class AppConstants {
  static const String appName = 'Inspeção Aérea de Torres';
  static const String appVersion = '1.0.0';

  // Supabase Producao (VPS Hostinger - via proxy Nginx porta 3000)
  static const String supabaseUrl = 'http://2.24.200.178:3000';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzc2MjA4NTUzLCJleHAiOjIwOTE1Njg1NTN9.52djmmT8KdN2N_dkrYDCUdbV7xF_gyvL4Y7xlpR0bEU';

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
