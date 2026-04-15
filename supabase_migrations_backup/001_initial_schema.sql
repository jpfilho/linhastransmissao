-- ============================================================
-- Inspeção Aérea de Torres - Schema Inicial
-- ============================================================

-- Extensão para cálculos geográficos
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- PERFIS DE USUÁRIO
-- ============================================================
CREATE TYPE user_role AS ENUM ('administrador', 'analista', 'visualizador');

CREATE TABLE perfis (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nome TEXT NOT NULL,
  email TEXT NOT NULL,
  role user_role NOT NULL DEFAULT 'visualizador',
  ativo BOOLEAN NOT NULL DEFAULT TRUE,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- LINHAS DE TRANSMISSÃO
-- ============================================================
CREATE TABLE linhas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nome TEXT NOT NULL,
  codigo TEXT UNIQUE,
  regional TEXT,
  tensao TEXT,
  extensao_km DOUBLE PRECISION,
  observacoes TEXT,
  geometria_json JSONB,  -- GeoJSON LineString
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- TORRES
-- ============================================================
CREATE TYPE criticidade_enum AS ENUM ('baixa', 'media', 'alta', 'critica');

CREATE TABLE torres (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  linha_id UUID REFERENCES linhas(id) ON DELETE SET NULL,
  codigo_torre TEXT NOT NULL,
  descricao TEXT,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  altitude DOUBLE PRECISION,
  tipo TEXT,
  geometria_json JSONB,
  criticidade_atual criticidade_enum DEFAULT 'baixa',
  observacoes TEXT,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(linha_id, codigo_torre)
);

CREATE INDEX idx_torres_linha ON torres(linha_id);
CREATE INDEX idx_torres_criticidade ON torres(criticidade_atual);

-- ============================================================
-- VÃOS (entre torres)
-- ============================================================
CREATE TABLE vaos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  linha_id UUID REFERENCES linhas(id) ON DELETE CASCADE,
  torre_origem_id UUID REFERENCES torres(id) ON DELETE CASCADE,
  torre_destino_id UUID REFERENCES torres(id) ON DELETE CASCADE,
  distancia_m DOUBLE PRECISION,
  observacoes TEXT,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- CAMPANHAS DE INSPEÇÃO
-- ============================================================
CREATE TYPE status_campanha AS ENUM ('planejada', 'em_andamento', 'concluida', 'cancelada');

CREATE TABLE campanhas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nome TEXT NOT NULL,
  descricao TEXT,
  data_inicio DATE,
  data_fim DATE,
  status status_campanha NOT NULL DEFAULT 'planejada',
  criado_por UUID REFERENCES perfis(id),
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- FOTOS
-- ============================================================
CREATE TYPE status_associacao AS ENUM ('associada', 'pendente', 'sem_gps', 'manual');
CREATE TYPE status_avaliacao AS ENUM ('nao_avaliada', 'avaliada', 'em_revisao');

CREATE TABLE fotos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  campanha_id UUID REFERENCES campanhas(id) ON DELETE SET NULL,
  linha_id UUID REFERENCES linhas(id) ON DELETE SET NULL,
  torre_id UUID REFERENCES torres(id) ON DELETE SET NULL,
  vao_id UUID REFERENCES vaos(id) ON DELETE SET NULL,
  nome_arquivo TEXT NOT NULL,
  caminho_storage TEXT NOT NULL,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  altitude DOUBLE PRECISION,
  data_hora_captura TIMESTAMPTZ,
  azimute DOUBLE PRECISION,
  distancia_torre_m DOUBLE PRECISION,
  status_associacao status_associacao NOT NULL DEFAULT 'pendente',
  qualidade_imagem DOUBLE PRECISION DEFAULT 0,
  status_avaliacao status_avaliacao NOT NULL DEFAULT 'nao_avaliada',
  resultado_preclassificacao TEXT,
  metadados_exif JSONB,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_fotos_campanha ON fotos(campanha_id);
CREATE INDEX idx_fotos_torre ON fotos(torre_id);
CREATE INDEX idx_fotos_linha ON fotos(linha_id);
CREATE INDEX idx_fotos_status_avaliacao ON fotos(status_avaliacao);
CREATE INDEX idx_fotos_status_associacao ON fotos(status_associacao);

-- ============================================================
-- AVALIAÇÕES DE FOTO
-- ============================================================
CREATE TYPE categoria_foto AS ENUM (
  'torre_completa', 'estrutura_metalica', 'isolador',
  'cabo', 'vegetacao', 'acesso', 'fundacao', 'outro'
);
CREATE TYPE qualidade_foto AS ENUM ('ruim', 'media', 'boa');

CREATE TABLE avaliacoes_foto (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  foto_id UUID NOT NULL REFERENCES fotos(id) ON DELETE CASCADE,
  usuario_id UUID REFERENCES perfis(id),
  imagem_util BOOLEAN,
  categoria categoria_foto,
  qualidade qualidade_foto,
  observacoes TEXT,
  necessita_inspecao_complementar BOOLEAN DEFAULT FALSE,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_avaliacoes_foto ON avaliacoes_foto(foto_id);

-- ============================================================
-- ANOMALIAS
-- ============================================================
CREATE TYPE tipo_anomalia AS ENUM (
  'corrosao', 'vegetacao_proxima', 'componente_danificado',
  'estrutura_inclinada', 'fundacao_problema', 'acesso_comprometido',
  'ocupacao_irregular', 'queimadas_proximas', 'outro'
);
CREATE TYPE severidade_enum AS ENUM ('baixa', 'media', 'alta', 'critica');
CREATE TYPE status_anomalia AS ENUM ('aberta', 'em_analise', 'resolvida', 'monitoramento');

CREATE TABLE anomalias (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  foto_id UUID REFERENCES fotos(id) ON DELETE SET NULL,
  torre_id UUID REFERENCES torres(id) ON DELETE SET NULL,
  tipo tipo_anomalia NOT NULL,
  severidade severidade_enum NOT NULL DEFAULT 'media',
  descricao TEXT,
  recomendacao TEXT,
  status status_anomalia NOT NULL DEFAULT 'aberta',
  criado_por UUID REFERENCES perfis(id),
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_anomalias_torre ON anomalias(torre_id);
CREATE INDEX idx_anomalias_tipo ON anomalias(tipo);
CREATE INDEX idx_anomalias_severidade ON anomalias(severidade);

-- ============================================================
-- FILA DE REVISÃO
-- ============================================================
CREATE TABLE fila_revisao (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  foto_id UUID NOT NULL REFERENCES fotos(id) ON DELETE CASCADE,
  motivo TEXT NOT NULL,
  prioridade INTEGER NOT NULL DEFAULT 0,
  revisado BOOLEAN DEFAULT FALSE,
  revisado_por UUID REFERENCES perfis(id),
  revisado_em TIMESTAMPTZ,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_fila_revisao_prioridade ON fila_revisao(prioridade DESC);

-- ============================================================
-- RESULTADOS IA (preparação futura)
-- ============================================================
CREATE TABLE resultados_ia (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  foto_id UUID NOT NULL REFERENCES fotos(id) ON DELETE CASCADE,
  modelo_versao TEXT,
  label_predita TEXT,
  score_confianca DOUBLE PRECISION,
  bounding_boxes_json JSONB,
  mascaras_json JSONB,
  status_validacao_humana TEXT DEFAULT 'pendente',
  revisado_por UUID REFERENCES perfis(id),
  revisado_em TIMESTAMPTZ,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_resultados_ia_foto ON resultados_ia(foto_id);

-- ============================================================
-- TRIGGER para atualizar atualizado_em
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.atualizado_em = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_linhas_updated_at BEFORE UPDATE ON linhas FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_torres_updated_at BEFORE UPDATE ON torres FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_campanhas_updated_at BEFORE UPDATE ON campanhas FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_anomalias_updated_at BEFORE UPDATE ON anomalias FOR EACH ROW EXECUTE FUNCTION update_updated_at();
