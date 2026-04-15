-- ============================================================
-- Funções do Banco de Dados
-- ============================================================

-- ============================================================
-- Cálculo de distância usando Haversine (retorna metros)
-- ============================================================
CREATE OR REPLACE FUNCTION calcular_distancia_metros(
  lat1 DOUBLE PRECISION, lng1 DOUBLE PRECISION,
  lat2 DOUBLE PRECISION, lng2 DOUBLE PRECISION
) RETURNS DOUBLE PRECISION AS $$
DECLARE
  R CONSTANT DOUBLE PRECISION := 6371000; -- raio da Terra em metros
  dlat DOUBLE PRECISION;
  dlng DOUBLE PRECISION;
  a DOUBLE PRECISION;
  c DOUBLE PRECISION;
BEGIN
  dlat := RADIANS(lat2 - lat1);
  dlng := RADIANS(lng2 - lng1);
  a := SIN(dlat / 2) ^ 2 + COS(RADIANS(lat1)) * COS(RADIANS(lat2)) * SIN(dlng / 2) ^ 2;
  c := 2 * ATAN2(SQRT(a), SQRT(1 - a));
  RETURN R * c;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================
-- Associar fotos de uma campanha às torres mais próximas
-- ============================================================
CREATE OR REPLACE FUNCTION associar_fotos_torres(
  p_campanha_id UUID,
  p_raio_maximo DOUBLE PRECISION DEFAULT 500
) RETURNS TABLE(
  foto_id UUID,
  torre_id UUID,
  distancia DOUBLE PRECISION,
  status TEXT
) AS $$
DECLARE
  r_foto RECORD;
  r_torre RECORD;
  v_menor_distancia DOUBLE PRECISION;
  v_segunda_distancia DOUBLE PRECISION;
  v_torre_mais_proxima UUID;
BEGIN
  FOR r_foto IN
    SELECT f.id, f.latitude, f.longitude
    FROM fotos f
    WHERE f.campanha_id = p_campanha_id
      AND f.latitude IS NOT NULL
      AND f.longitude IS NOT NULL
  LOOP
    v_menor_distancia := 999999;
    v_segunda_distancia := 999999;
    v_torre_mais_proxima := NULL;

    FOR r_torre IN
      SELECT t.id, t.latitude, t.longitude FROM torres t
    LOOP
      DECLARE
        v_dist DOUBLE PRECISION;
      BEGIN
        v_dist := calcular_distancia_metros(
          r_foto.latitude, r_foto.longitude,
          r_torre.latitude, r_torre.longitude
        );
        IF v_dist < v_menor_distancia THEN
          v_segunda_distancia := v_menor_distancia;
          v_menor_distancia := v_dist;
          v_torre_mais_proxima := r_torre.id;
        ELSIF v_dist < v_segunda_distancia THEN
          v_segunda_distancia := v_dist;
        END IF;
      END;
    END LOOP;

    IF v_menor_distancia <= p_raio_maximo THEN
      -- Ambiguidade: se a segunda torre está muito próxima (< 20% de diferença)
      IF v_segunda_distancia < v_menor_distancia * 1.2 THEN
        UPDATE fotos SET
          torre_id = v_torre_mais_proxima,
          distancia_torre_m = v_menor_distancia,
          status_associacao = 'pendente'
        WHERE fotos.id = r_foto.id;

        foto_id := r_foto.id;
        torre_id := v_torre_mais_proxima;
        distancia := v_menor_distancia;
        status := 'pendente';
        RETURN NEXT;
      ELSE
        UPDATE fotos SET
          torre_id = v_torre_mais_proxima,
          distancia_torre_m = v_menor_distancia,
          status_associacao = 'associada'
        WHERE fotos.id = r_foto.id;

        foto_id := r_foto.id;
        torre_id := v_torre_mais_proxima;
        distancia := v_menor_distancia;
        status := 'associada';
        RETURN NEXT;
      END IF;
    ELSE
      UPDATE fotos SET
        status_associacao = 'pendente',
        distancia_torre_m = v_menor_distancia
      WHERE fotos.id = r_foto.id;

      foto_id := r_foto.id;
      torre_id := NULL;
      distancia := v_menor_distancia;
      status := 'fora_do_raio';
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Calcular criticidade de uma torre
-- ============================================================
CREATE OR REPLACE FUNCTION calcular_criticidade_torre(p_torre_id UUID)
RETURNS criticidade_enum AS $$
DECLARE
  v_total_anomalias INTEGER;
  v_anomalias_criticas INTEGER;
  v_anomalias_altas INTEGER;
  v_fotos_ruins INTEGER;
  v_pendencias INTEGER;
  v_score INTEGER := 0;
BEGIN
  SELECT COUNT(*) INTO v_total_anomalias
  FROM anomalias WHERE torre_id = p_torre_id AND status != 'resolvida';

  SELECT COUNT(*) INTO v_anomalias_criticas
  FROM anomalias WHERE torre_id = p_torre_id AND severidade = 'critica' AND status != 'resolvida';

  SELECT COUNT(*) INTO v_anomalias_altas
  FROM anomalias WHERE torre_id = p_torre_id AND severidade = 'alta' AND status != 'resolvida';

  SELECT COUNT(*) INTO v_fotos_ruins
  FROM fotos f JOIN avaliacoes_foto a ON a.foto_id = f.id
  WHERE f.torre_id = p_torre_id AND a.qualidade = 'ruim';

  SELECT COUNT(*) INTO v_pendencias
  FROM fotos WHERE torre_id = p_torre_id AND status_avaliacao = 'nao_avaliada';

  -- Score calculation
  v_score := v_score + (v_anomalias_criticas * 10);
  v_score := v_score + (v_anomalias_altas * 5);
  v_score := v_score + (v_total_anomalias * 2);
  v_score := v_score + (v_fotos_ruins * 1);
  v_score := v_score + (v_pendencias * 1);

  -- Update and return
  IF v_score >= 20 THEN
    UPDATE torres SET criticidade_atual = 'critica' WHERE id = p_torre_id;
    RETURN 'critica';
  ELSIF v_score >= 10 THEN
    UPDATE torres SET criticidade_atual = 'alta' WHERE id = p_torre_id;
    RETURN 'alta';
  ELSIF v_score >= 5 THEN
    UPDATE torres SET criticidade_atual = 'media' WHERE id = p_torre_id;
    RETURN 'media';
  ELSE
    UPDATE torres SET criticidade_atual = 'baixa' WHERE id = p_torre_id;
    RETURN 'baixa';
  END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- View: Estatísticas do Dashboard
-- ============================================================
CREATE OR REPLACE VIEW v_dashboard_stats AS
SELECT
  (SELECT COUNT(*) FROM linhas) AS total_linhas,
  (SELECT COUNT(*) FROM torres) AS total_torres,
  (SELECT COUNT(*) FROM fotos) AS total_fotos,
  (SELECT COUNT(*) FROM fotos WHERE status_associacao = 'pendente' OR status_associacao = 'sem_gps') AS fotos_sem_associacao,
  (SELECT COUNT(*) FROM fotos WHERE status_avaliacao = 'nao_avaliada') AS fotos_sem_avaliacao,
  (SELECT COUNT(*) FROM torres WHERE criticidade_atual IN ('alta', 'critica')) AS torres_criticas,
  (SELECT COUNT(*) FROM anomalias WHERE status != 'resolvida') AS anomalias_abertas,
  (SELECT COUNT(*) FROM campanhas WHERE status = 'em_andamento') AS campanhas_ativas;

-- ============================================================
-- View: Anomalias por tipo
-- ============================================================
CREATE OR REPLACE VIEW v_anomalias_por_tipo AS
SELECT tipo, COUNT(*) AS total
FROM anomalias
WHERE status != 'resolvida'
GROUP BY tipo
ORDER BY total DESC;
