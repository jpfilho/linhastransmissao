# =============================================================
# SUPABASE DEPLOY - Usando docker run (sem docker compose)
# Cole e execute este script no servidor 10.140.50.10
# Versao final com todos os fixes para LCOW no Windows Server
# =============================================================

Set-Location "C:\aplicativos\fotos_h_supabase"

# ======== CONFIGURACOES ========
$NET     = "supabase_network_fotos_h_supabase"
$PGPW    = "postgres"
$JWT     = "super-secret-jwt-token-with-at-least-32-characters-long"
$ANON    = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRFA0NiK7kyqd918Os5P6q2nd23OfmoxKSmUMOuNOrE"
$SKEY    = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hj04zWl196z2-SBc0"
$API_URL = "http://10.140.50.10:54321"
$SKB     = "UpNVntn3cDxHJpq99YMc1T1AQgQpc8kfYTuRgBiYa15BLrx8etQoXz3gZv1/u2oq"
$KONG_DIR = "C:\aplicativos\fotos_h_supabase\kong-config"

Write-Host "=== SUPABASE DEPLOY (docker run) ===" -ForegroundColor Cyan

# ======== LIMPAR CONTAINERS ANTIGOS ========
Write-Host "`n[1/9] Limpando containers antigos..." -ForegroundColor Yellow
$containers = @("supabase_db","supabase_auth","supabase_rest","supabase_realtime",
                "supabase_storage","supabase_imgproxy","supabase_meta",
                "supabase_studio","supabase_kong","supabase_mailpit","supabase_vector")
foreach ($c in $containers) {
    docker stop $c 2>$null | Out-Null
    docker rm $c 2>$null | Out-Null
}

# ======== REDE ========
Write-Host "`n[2/9] Criando rede NAT..." -ForegroundColor Yellow
docker network rm $NET 2>$null | Out-Null
docker network create --driver=nat $NET | Out-Null
Write-Host "  Rede criada: $NET" -ForegroundColor Green

# ======== VOLUMES ========
Write-Host "`n[3/9] Criando volumes..." -ForegroundColor Yellow
docker volume create supabase_db_fotos_h_supabase 2>$null | Out-Null
docker volume create supabase_storage_fotos_h_supabase 2>$null | Out-Null
Write-Host "  Volumes criados" -ForegroundColor Green

# ======== KONG CONFIG DIR (LCOW nao suporta file bind mounts, so diretorios) ========
Write-Host "`n  Preparando diretorio do Kong..." -ForegroundColor DarkYellow
New-Item -ItemType Directory -Path $KONG_DIR -Force | Out-Null
if (Test-Path "C:\aplicativos\fotos_h_supabase\kong.yml") {
    Copy-Item "C:\aplicativos\fotos_h_supabase\kong.yml" "$KONG_DIR\" -Force
}
# Corrigir nomes de container no kong.yml (usar supabase_* em vez de nomes curtos)
$kongPath = "$KONG_DIR\kong.yml"
if (Test-Path $kongPath) {
    $content = Get-Content $kongPath -Raw
    $content = $content -replace 'http://auth:',      'http://supabase_auth:'
    $content = $content -replace 'http://rest:',      'http://supabase_rest:'
    $content = $content -replace 'http://realtime:',  'http://supabase_realtime:'
    $content = $content -replace 'http://storage:',   'http://supabase_storage:'
    $content = $content -replace 'http://meta:',      'http://supabase_meta:'
    $content = $content -replace 'http://mailpit:',   'http://supabase_mailpit:'
    $content | Set-Content $kongPath -Encoding UTF8
    Write-Host "  kong.yml atualizado com nomes de container corretos" -ForegroundColor Green
}

# ======== BANCO DE DADOS ========
Write-Host "`n[4/9] Iniciando PostgreSQL 17..." -ForegroundColor Yellow
docker run -d --name supabase_db --network $NET --add-host "host.docker.internal:10.140.50.10" --restart unless-stopped -p 54322:5432 -v supabase_db_fotos_h_supabase:/var/lib/postgresql/data -e POSTGRES_HOST=/var/run/postgresql -e PGPORT=5432 -e POSTGRES_PASSWORD=$PGPW -e PGPASSWORD=$PGPW -e POSTGRES_DB=postgres -e JWT_SECRET=$JWT -e JWT_EXP=3600 "public.ecr.aws/supabase/postgres:17.6.1.066"

# Aguardar DB ficar saudavel
Write-Host "  Aguardando DB ficar saudavel (max 120s)..." -ForegroundColor DarkYellow
$t = 0; $healthy = $false
while ($t -lt 120) {
    Start-Sleep 5; $t += 5
    $h = docker inspect supabase_db --format "{{.State.Health.Status}}" 2>$null
    Write-Host "    $t s - status: $h"
    if ($h -eq "healthy") { $healthy = $true; break }
}
if (-not $healthy) {
    Write-Host "  AVISO: DB nao saudavel apos 120s! Logs:" -ForegroundColor Red
    docker logs supabase_db --tail 20
    exit 1
} else {
    Write-Host "  DB SAUDAVEL!" -ForegroundColor Green
}

# ======== FIX PG_HBA: trust para rede interna Docker ========
Write-Host "`n  Configurando pg_hba.conf (trust para rede Docker interna)..." -ForegroundColor DarkYellow
docker exec supabase_db bash -c "HBA=`$(psql -U postgres -t -c 'SHOW hba_file;' | xargs) && grep -q '172.0.0.0/8' `$HBA || sed -i 's|# IPv4 external connections|# Docker internal trust\nhost all all 172.0.0.0/8 trust\n\n# IPv4 external connections|' `$HBA && psql -U postgres -c 'SELECT pg_reload_conf();' > /dev/null && echo 'HBA OK'"

# ======== FIX: Criar schemas necessarios ========
Write-Host "  Criando schemas necessarios..." -ForegroundColor DarkYellow
docker exec supabase_db psql -U postgres -c "
CREATE SCHEMA IF NOT EXISTS _realtime;
CREATE SCHEMA IF NOT EXISTS realtime;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS extensions;
GRANT ALL ON SCHEMA _realtime  TO postgres;
GRANT ALL ON SCHEMA auth       TO postgres;
GRANT ALL ON SCHEMA storage    TO postgres;
GRANT ALL ON SCHEMA extensions TO postgres;
" 2>$null | Out-Null
Write-Host "  Schemas criados" -ForegroundColor Green

# ======== AUTH (GoTrue) ========
Write-Host "`n[5/9] Iniciando Auth (GoTrue)..." -ForegroundColor Yellow
docker run -d --name supabase_auth --network $NET --add-host "host.docker.internal:10.140.50.10" --restart unless-stopped -e GOTRUE_API_HOST=0.0.0.0 -e GOTRUE_API_PORT=9999 -e "API_EXTERNAL_URL=$API_URL" -e GOTRUE_DB_DRIVER=postgres -e "GOTRUE_DB_DATABASE_URL=postgres://supabase_auth_admin@supabase_db:5432/postgres" -e "GOTRUE_SITE_URL=$API_URL" -e GOTRUE_DISABLE_SIGNUP=false -e GOTRUE_JWT_ADMIN_ROLES=service_role -e GOTRUE_JWT_AUD=authenticated -e GOTRUE_JWT_DEFAULT_GROUP_NAME=authenticated -e GOTRUE_JWT_EXP=3600 -e "GOTRUE_JWT_SECRET=$JWT" -e GOTRUE_MAILER_AUTOCONFIRM=true -e GOTRUE_SMTP_HOST=supabase_mailpit -e GOTRUE_SMTP_PORT=1025 -e GOTRUE_EXTERNAL_PHONE_ENABLED=false -e GOTRUE_MAILER_URLPATHS_INVITE=/auth/v1/verify -e GOTRUE_MAILER_URLPATHS_CONFIRMATION=/auth/v1/verify -e GOTRUE_MAILER_URLPATHS_RECOVERY=/auth/v1/verify "public.ecr.aws/supabase/gotrue:v2.184.0"
Write-Host "  Auth iniciado" -ForegroundColor Green

# ======== REST (PostgREST) ========
Write-Host "`n[5/9] Iniciando REST (PostgREST)..." -ForegroundColor Yellow
docker run -d --name supabase_rest --network $NET --add-host "host.docker.internal:10.140.50.10" --restart unless-stopped -e "PGRST_DB_URI=postgres://authenticator@supabase_db:5432/postgres" -e PGRST_DB_SCHEMAS=public,storage,graphql_public -e PGRST_DB_ANON_ROLE=anon -e "PGRST_JWT_SECRET=$JWT" -e PGRST_DB_USE_LEGACY_GUCS=false -e "PGRST_APP_SETTINGS_JWT_SECRET=$JWT" -e PGRST_APP_SETTINGS_JWT_EXP=3600 "public.ecr.aws/supabase/postgrest:v14.1"
Write-Host "  REST iniciado" -ForegroundColor Green

# ======== REALTIME (v2.69.0 - fix APP_NAME, RLIMIT_NOFILE=1024) ========
Write-Host "`n[5/9] Iniciando Realtime..." -ForegroundColor Yellow
docker run -d --name supabase_realtime --network $NET --add-host "host.docker.internal:10.140.50.10" --restart unless-stopped -e PORT=4000 -e DB_HOST=supabase_db -e DB_PORT=5432 -e DB_USER=supabase_admin -e DB_PASSWORD=$PGPW -e DB_NAME=postgres -e "DB_AFTER_CONNECT_QUERY=SET search_path = _realtime" -e DB_ENC_KEY=supabaseEncryptedKeyForLocalDev00001 -e "API_JWT_SECRET=$JWT" -e FLY_ALLOC_ID=fly123 -e FLY_APP_NAME=realtime -e APP_NAME=realtime -e "SECRET_KEY_BASE=$SKB" -e "ERL_AFLAGS=-proto_dist inet_tcp" -e ENABLE_TAILSCALE=false -e "DNS_NODES=''" -e RLIMIT_NOFILE=1024 "public.ecr.aws/supabase/realtime:v2.69.0"
Write-Host "  Realtime iniciado" -ForegroundColor Green

# ======== STORAGE ========
Write-Host "`n[6/9] Iniciando Storage..." -ForegroundColor Yellow
docker run -d --name supabase_storage --network $NET --add-host "host.docker.internal:10.140.50.10" --restart unless-stopped -v supabase_storage_fotos_h_supabase:/var/lib/storage -e "ANON_KEY=$ANON" -e "SERVICE_KEY=$SKEY" -e POSTGREST_URL=http://supabase_rest:3000 -e "PGRST_JWT_SECRET=$JWT" -e "DATABASE_URL=postgres://supabase_storage_admin@supabase_db:5432/postgres" -e FILE_SIZE_LIMIT=52428800 -e STORAGE_BACKEND=file -e FILE_STORAGE_BACKEND_PATH=/var/lib/storage -e TENANT_ID=fotos_h_supabase -e REGION=local -e GLOBAL_S3_BUCKET=stub -e ENABLE_IMAGE_TRANSFORMATION=true -e IMGPROXY_URL=http://supabase_imgproxy:5001 "public.ecr.aws/supabase/storage-api:v1.33.1"
Write-Host "  Storage iniciado" -ForegroundColor Green

# ======== IMGPROXY ========
docker run -d --name supabase_imgproxy --network $NET --add-host "host.docker.internal:10.140.50.10" --restart unless-stopped -v supabase_storage_fotos_h_supabase:/var/lib/storage:ro -e IMGPROXY_BIND=:5001 -e IMGPROXY_LOCAL_FILESYSTEM_ROOT=/ -e IMGPROXY_USE_ETAG=true "public.ecr.aws/supabase/imgproxy:v3.8.0" | Out-Null

# ======== META ========
docker run -d --name supabase_meta --network $NET --add-host "host.docker.internal:10.140.50.10" --restart unless-stopped -e PG_META_PORT=8080 -e PG_META_DB_HOST=supabase_db -e PG_META_DB_PORT=5432 -e PG_META_DB_NAME=postgres -e PG_META_DB_USER=supabase_admin -e PG_META_DB_PASSWORD=$PGPW "public.ecr.aws/supabase/postgres-meta:v0.95.1" | Out-Null

# ======== STUDIO ========
Write-Host "`n[7/9] Iniciando Studio..." -ForegroundColor Yellow
docker run -d --name supabase_studio --network $NET --add-host "host.docker.internal:10.140.50.10" --restart unless-stopped -p 54323:3000 -e STUDIO_PG_META_URL=http://supabase_meta:8080 -e POSTGRES_PASSWORD=$PGPW -e DEFAULT_ORGANIZATION_NAME=Eletronorte -e "DEFAULT_PROJECT_NAME=Inspecao Torres" -e SUPABASE_URL=http://supabase_kong:8000 -e "SUPABASE_PUBLIC_URL=$API_URL" -e "SUPABASE_ANON_KEY=$ANON" -e "SUPABASE_SERVICE_KEY=$SKEY" -e "AUTH_JWT_SECRET=$JWT" -e NEXT_TELEMETRY_DISABLED=1 "public.ecr.aws/supabase/studio:2025.12.17-sha-43f4f7f"
Write-Host "  Studio iniciado" -ForegroundColor Green

# ======== MAILPIT ========
docker run -d --name supabase_mailpit --network $NET --add-host "host.docker.internal:10.140.50.10" --restart unless-stopped -p 54324:8025 "public.ecr.aws/supabase/mailpit:v1.22.3" | Out-Null

# ======== KONG (API Gateway) - usa DIRETORIO (LCOW nao suporta file bind mounts) ========
Write-Host "`n[8/9] Iniciando Kong..." -ForegroundColor Yellow
docker run -d --name supabase_kong --network $NET --add-host "host.docker.internal:10.140.50.10" --restart unless-stopped -p 54321:8000 -p 54320:8001 -v "${KONG_DIR}:/home/kong:ro" -e KONG_DATABASE=off -e KONG_DECLARATIVE_CONFIG=/home/kong/kong.yml -e KONG_DNS_ORDER=LAST,A,CNAME -e "KONG_PLUGINS=request-transformer,cors,key-auth,acl,basic-auth" -e KONG_NGINX_PROXY_PROXY_BUFFER_SIZE=160k -e "KONG_NGINX_PROXY_PROXY_BUFFERS=64 160k" "public.ecr.aws/supabase/kong:2.8.1"
Write-Host "  Kong iniciado" -ForegroundColor Green

# ======== RESULTADO ========
Write-Host "`n[9/9] Status final dos containers..." -ForegroundColor Yellow
Start-Sleep 15
docker ps --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}"

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host " SUPABASE RODANDO!" -ForegroundColor Green
Write-Host "  API URL  : http://10.140.50.10:54321" -ForegroundColor White
Write-Host "  Studio   : http://10.140.50.10:54323" -ForegroundColor White
Write-Host "  Database : 10.140.50.10:54322" -ForegroundColor White
Write-Host "  ANON KEY : $ANON" -ForegroundColor DarkCyan
Write-Host "======================================================" -ForegroundColor Green

# ======== TESTE RAPIDO DA API ========
Write-Host "`n=== TESTE DA API ===" -ForegroundColor Cyan
Start-Sleep 5
try {
    $r = Invoke-WebRequest -Uri "http://10.140.50.10:54321/rest/v1/" -Headers @{"apikey"=$ANON} -UseBasicParsing
    Write-Host "  REST: OK (HTTP $($r.StatusCode))" -ForegroundColor Green
} catch { Write-Host "  REST: FALHOU - $($_.Exception.Message)" -ForegroundColor Red }

try {
    $r = Invoke-WebRequest -Uri "http://10.140.50.10:54321/auth/v1/settings" -Headers @{"apikey"=$ANON} -UseBasicParsing
    Write-Host "  AUTH: OK (HTTP $($r.StatusCode))" -ForegroundColor Green
} catch { Write-Host "  AUTH: FALHOU - $($_.Exception.Message)" -ForegroundColor Red }
