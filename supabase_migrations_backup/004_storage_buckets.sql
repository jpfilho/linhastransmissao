-- ============================================================
-- Storage Buckets Configuration
-- ============================================================
-- Execute via Supabase Dashboard > Storage > Create Bucket
-- Ou via API

-- Bucket: fotos-inspecao
-- Público: NÃO (requer autenticação)
-- Tamanho máximo: 50MB
-- Tipos permitidos: image/jpeg, image/png, image/tiff, image/webp

-- Estrutura de pastas recomendada:
-- fotos-inspecao/
--   {campanha_id}/
--     {linha_codigo}/
--       {data_yyyy-mm-dd}/
--         {nome_arquivo}

-- Para criar o bucket via SQL (Supabase):
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'fotos-inspecao',
  'fotos-inspecao',
  FALSE,
  52428800, -- 50MB
  ARRAY['image/jpeg', 'image/png', 'image/tiff', 'image/webp']
);

-- ============================================================
-- Storage Policies
-- ============================================================

-- Usuários autenticados podem ler imagens
CREATE POLICY "storage_read_authenticated"
ON storage.objects FOR SELECT
USING (
  bucket_id = 'fotos-inspecao'
  AND auth.role() = 'authenticated'
);

-- Admin e analistas podem fazer upload
CREATE POLICY "storage_insert_authorized"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'fotos-inspecao'
  AND auth.role() = 'authenticated'
  AND (SELECT role FROM perfis WHERE id = auth.uid()) IN ('administrador', 'analista')
);

-- Admin pode deletar
CREATE POLICY "storage_delete_admin"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'fotos-inspecao'
  AND (SELECT role FROM perfis WHERE id = auth.uid()) = 'administrador'
);
