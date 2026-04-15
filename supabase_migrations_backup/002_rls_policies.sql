-- ============================================================
-- Row Level Security Policies
-- ============================================================

-- Habilitar RLS em todas as tabelas
ALTER TABLE perfis ENABLE ROW LEVEL SECURITY;
ALTER TABLE linhas ENABLE ROW LEVEL SECURITY;
ALTER TABLE torres ENABLE ROW LEVEL SECURITY;
ALTER TABLE vaos ENABLE ROW LEVEL SECURITY;
ALTER TABLE campanhas ENABLE ROW LEVEL SECURITY;
ALTER TABLE fotos ENABLE ROW LEVEL SECURITY;
ALTER TABLE avaliacoes_foto ENABLE ROW LEVEL SECURITY;
ALTER TABLE anomalias ENABLE ROW LEVEL SECURITY;
ALTER TABLE fila_revisao ENABLE ROW LEVEL SECURITY;
ALTER TABLE resultados_ia ENABLE ROW LEVEL SECURITY;

-- Helper function para obter role do usuário
CREATE OR REPLACE FUNCTION get_user_role()
RETURNS user_role AS $$
  SELECT role FROM perfis WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ============================================================
-- PERFIS
-- ============================================================
CREATE POLICY "perfis_select" ON perfis FOR SELECT USING (true);
CREATE POLICY "perfis_update_own" ON perfis FOR UPDATE USING (id = auth.uid());
CREATE POLICY "perfis_admin_all" ON perfis FOR ALL USING (get_user_role() = 'administrador');

-- ============================================================
-- LINHAS - todos leem, admin/analista escrevem
-- ============================================================
CREATE POLICY "linhas_select" ON linhas FOR SELECT USING (true);
CREATE POLICY "linhas_insert" ON linhas FOR INSERT WITH CHECK (
  get_user_role() IN ('administrador', 'analista')
);
CREATE POLICY "linhas_update" ON linhas FOR UPDATE USING (
  get_user_role() IN ('administrador', 'analista')
);
CREATE POLICY "linhas_delete" ON linhas FOR DELETE USING (
  get_user_role() = 'administrador'
);

-- ============================================================
-- TORRES
-- ============================================================
CREATE POLICY "torres_select" ON torres FOR SELECT USING (true);
CREATE POLICY "torres_insert" ON torres FOR INSERT WITH CHECK (
  get_user_role() IN ('administrador', 'analista')
);
CREATE POLICY "torres_update" ON torres FOR UPDATE USING (
  get_user_role() IN ('administrador', 'analista')
);
CREATE POLICY "torres_delete" ON torres FOR DELETE USING (
  get_user_role() = 'administrador'
);

-- ============================================================
-- VAOS
-- ============================================================
CREATE POLICY "vaos_select" ON vaos FOR SELECT USING (true);
CREATE POLICY "vaos_modify" ON vaos FOR ALL USING (
  get_user_role() IN ('administrador', 'analista')
);

-- ============================================================
-- CAMPANHAS
-- ============================================================
CREATE POLICY "campanhas_select" ON campanhas FOR SELECT USING (true);
CREATE POLICY "campanhas_insert" ON campanhas FOR INSERT WITH CHECK (
  get_user_role() IN ('administrador', 'analista')
);
CREATE POLICY "campanhas_update" ON campanhas FOR UPDATE USING (
  get_user_role() IN ('administrador', 'analista')
);

-- ============================================================
-- FOTOS
-- ============================================================
CREATE POLICY "fotos_select" ON fotos FOR SELECT USING (true);
CREATE POLICY "fotos_insert" ON fotos FOR INSERT WITH CHECK (
  get_user_role() IN ('administrador', 'analista')
);
CREATE POLICY "fotos_update" ON fotos FOR UPDATE USING (
  get_user_role() IN ('administrador', 'analista')
);

-- ============================================================
-- AVALIAÇÕES
-- ============================================================
CREATE POLICY "avaliacoes_select" ON avaliacoes_foto FOR SELECT USING (true);
CREATE POLICY "avaliacoes_insert" ON avaliacoes_foto FOR INSERT WITH CHECK (
  get_user_role() IN ('administrador', 'analista')
);
CREATE POLICY "avaliacoes_update" ON avaliacoes_foto FOR UPDATE USING (
  get_user_role() IN ('administrador', 'analista')
);

-- ============================================================
-- ANOMALIAS
-- ============================================================
CREATE POLICY "anomalias_select" ON anomalias FOR SELECT USING (true);
CREATE POLICY "anomalias_insert" ON anomalias FOR INSERT WITH CHECK (
  get_user_role() IN ('administrador', 'analista')
);
CREATE POLICY "anomalias_update" ON anomalias FOR UPDATE USING (
  get_user_role() IN ('administrador', 'analista')
);

-- ============================================================
-- FILA REVISÃO
-- ============================================================
CREATE POLICY "fila_select" ON fila_revisao FOR SELECT USING (true);
CREATE POLICY "fila_modify" ON fila_revisao FOR ALL USING (
  get_user_role() IN ('administrador', 'analista')
);

-- ============================================================
-- RESULTADOS IA
-- ============================================================
CREATE POLICY "ia_select" ON resultados_ia FOR SELECT USING (true);
CREATE POLICY "ia_modify" ON resultados_ia FOR ALL USING (
  get_user_role() IN ('administrador', 'analista')
);
