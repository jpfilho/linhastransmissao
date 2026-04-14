# 🗼 Inspeção Aérea de Torres de Transmissão

Sistema profissional para análise e avaliação de imagens georreferenciadas de inspeção aérea de torres de transmissão.

## 📋 Funcionalidades

| Módulo | Descrição |
|--------|-----------|
| **Dashboard** | 8 KPIs, gráficos de anomalias, criticidade e fotos por campanha |
| **Mapa Interativo** | Visualização de torres, linhas e fotos com flutter_map |
| **Importação KMZ** | Upload e parsing de arquivos KMZ/KML com extração de geometrias |
| **Importação de Fotos** | Leitura EXIF, quality scoring, upload com progresso |
| **Gestão de Torres** | Listagem, filtros, detalhe com mini-mapa e galeria |
| **Gestão de Fotos** | Metadados, associação, avaliação técnica |
| **Avaliações** | Fila de revisão priorizada (não avaliadas, sem GPS, baixa qualidade) |
| **Anomalias** | Registro e listagem com tipo, severidade, status |
| **Comparação Temporal** | Side-by-side entre campanhas com avaliação de evolução |

## 🛠️ Stack

- **Frontend:** Flutter (Web, Desktop, Android)
- **Backend:** Supabase (Postgres, Storage, Auth, RLS)
- **State Management:** Riverpod
- **Navigation:** GoRouter
- **Maps:** flutter_map + OpenStreetMap
- **Charts:** fl_chart

## 🚀 Quick Start

```bash
# 1. Instalar dependências
flutter pub get

# 2. Rodar em modo demo (dados mockados, sem Supabase)
flutter run -d chrome
# ou
flutter run -d windows
```

## 📂 Estrutura do Projeto

```
lib/
├── app.dart                    # MaterialApp.router
├── main.dart                   # Entry point
├── core/
│   ├── config/
│   │   ├── app_constants.dart  # Constantes, labels, parâmetros
│   │   └── routes.dart         # GoRouter configuration
│   ├── theme/
│   │   ├── app_colors.dart     # Paleta de cores
│   │   └── app_theme.dart      # Tema dark profissional
│   └── utils/
│       ├── distance_calculator.dart  # Haversine
│       ├── exif_reader.dart          # Leitura EXIF
│       ├── kmz_parser.dart           # Parser KMZ/KML
│       └── quality_scorer.dart       # Score de qualidade
├── features/
│   ├── anomalias/          # Listagem + formulário
│   ├── avaliacoes/         # Fila de revisão
│   ├── comparacao_temporal/# Comparação side-by-side
│   ├── dashboard/          # KPIs e gráficos
│   ├── fotos/              # Listagem + detalhe
│   ├── importacao_fotos/   # Import com EXIF
│   ├── importacao_kmz/     # Import KMZ/KML
│   ├── mapa_inspecao/      # Mapa interativo
│   └── torres/             # Listagem + detalhe
└── shared/
    ├── models/             # Linha, Campanha
    ├── services/           # MockData
    └── widgets/            # StatsCard, Badges, etc.

supabase/migrations/
├── 001_initial_schema.sql  # Tabelas, enums, indexes, triggers
├── 002_rls_policies.sql    # Row Level Security
├── 003_functions.sql       # Haversine, associação, criticidade
└── 004_storage_buckets.sql # Bucket de fotos
```

## 🗄️ Configuração do Supabase

1. Crie um projeto no [supabase.com](https://supabase.com)
2. Execute os scripts SQL em ordem (`001` → `004`) no SQL Editor
3. Atualize `lib/core/config/app_constants.dart` com suas credenciais:

```dart
static const String supabaseUrl = 'https://SEU-PROJETO.supabase.co';
static const String supabaseAnonKey = 'sua-anon-key';
```

4. Descomente a inicialização do Supabase em `main.dart`

## 🎨 Demo Mode

O sistema roda em **modo demo** por padrão (sem Supabase), usando dados mockados realistas:
- 3 linhas de transmissão (500kV, 230kV, 138kV)
- 26 torres com coordenadas na região de Carajás/PA
- ~80 fotos com metadados EXIF simulados
- Anomalias com diferentes severidades
- 3 campanhas de inspeção

## 📝 Próximos Passos

- [ ] Autenticação (login, roles, auth guard)
- [ ] Integração real com Supabase (CRUD completo)
- [ ] Upload real de imagens para Supabase Storage
- [ ] Integração com modelos de IA para detecção automática
- [ ] Relatórios PDF exportáveis
- [ ] Modo offline para uso em campo
