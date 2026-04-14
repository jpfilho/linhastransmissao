# =============================================================
# SUPABASE SELF-HOSTED DEPLOY - Windows Server LCOW Fix
# Resolve o problema de /etc/hosts em containers LCOW
# =============================================================

$ErrorActionPreference = "Continue"
$PROJECT_DIR = "C:\aplicativos\fotos_h_supabase"
$COMPOSE_OUT = "$PROJECT_DIR\docker-compose-custom.yml"
$ENV_OUT = "$PROJECT_DIR\.env.custom"
$CONFIG_TOML = "$PROJECT_DIR\supabase\config.toml"

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " SUPABASE SELF-HOSTED DEPLOY (LCOW Fix)" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# --- STEP 1: Ler config.toml ---
Write-Host "`n[1/6] Lendo config.toml..." -ForegroundColor Yellow
if (-not (Test-Path $CONFIG_TOML)) {
    Write-Error "ERRO: config.toml nao encontrado em $CONFIG_TOML"
    exit 1
}
$config = Get-Content $CONFIG_TOML -Raw

function Get-TomlValue($content, $key) {
    $match = [regex]::Match($content, "(?m)^\s*$key\s*=\s*[`"']([^`"']*)[`"']")
    if ($match.Success) { return $match.Groups[1].Value }
    # Try without quotes (boolean/number)
    $match2 = [regex]::Match($content, "(?m)^\s*$key\s*=\s*([^\s#\r\n]+)")
    if ($match2.Success) { return $match2.Groups[1].Value }
    return ""
}

$JWT_SECRET = Get-TomlValue $config "jwt_secret"
$DB_PASSWORD = Get-TomlValue $config "password"
$PROJECT_ID = Get-TomlValue $config "project_id"

if (-not $JWT_SECRET) { $JWT_SECRET = "super-secret-jwt-token-with-at-least-32-characters-long" }
if (-not $DB_PASSWORD) { $DB_PASSWORD = "postgres" }
if (-not $PROJECT_ID) { $PROJECT_ID = "fotos_h_supabase" }

Write-Host "  Project ID : $PROJECT_ID"
Write-Host "  JWT Secret : $($JWT_SECRET.Substring(0, [Math]::Min(20, $JWT_SECRET.Length)))..."
Write-Host "  DB Password: $($DB_PASSWORD.Substring(0, [Math]::Min(4, $DB_PASSWORD.Length)))..."

# --- STEP 2: Gerar JWT tokens ---
Write-Host "`n[2/6] Gerando JWT tokens..." -ForegroundColor Yellow

function New-JWT($secret, $payloadJson) {
    $headerB64 = [Convert]::ToBase64String(
        [System.Text.Encoding]::UTF8.GetBytes('{"alg":"HS256","typ":"JWT"}')
    ).TrimEnd('=').Replace('+','-').Replace('/','_')
    
    $payloadB64 = [Convert]::ToBase64String(
        [System.Text.Encoding]::UTF8.GetBytes($payloadJson)
    ).TrimEnd('=').Replace('+','-').Replace('/','_')
    
    $sigInput = "$headerB64.$payloadB64"
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($secret)
    $sigBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sigInput))
    $sigB64 = [Convert]::ToBase64String($sigBytes).TrimEnd('=').Replace('+','-').Replace('/','_')
    return "$headerB64.$payloadB64.$sigB64"
}

# exp = far future (year 2033)
$ANON_KEY = New-JWT $JWT_SECRET '{"iss":"supabase-demo","role":"anon","exp":1983812996}'
$SERVICE_KEY = New-JWT $JWT_SECRET '{"iss":"supabase-demo","role":"service_role","exp":1983812996}'
Write-Host "  Anon key    : OK ($(($ANON_KEY).Length) chars)"
Write-Host "  Service key : OK ($(($SERVICE_KEY).Length) chars)"

# --- STEP 3: Detectar imagens Docker ---
Write-Host "`n[3/6] Detectando imagens Docker..." -ForegroundColor Yellow

function Get-DockerImage($pattern) {
    $img = docker images --format "{{.Repository}}:{{.Tag}}" 2>$null | 
           Where-Object { $_ -match $pattern -and $_ -notmatch "<none>" } | 
           Select-Object -First 1
    if ($img) { Write-Host "  OK: $img" } else { Write-Host "  FALTANDO: $pattern" -ForegroundColor Red }
    return $img
}

$IMG_DB         = Get-DockerImage "supabase/postgres:"
$IMG_STUDIO     = Get-DockerImage "supabase/studio:"
$IMG_KONG       = Get-DockerImage "/kong:"
$IMG_GOTRUE     = Get-DockerImage "supabase/gotrue:"
$IMG_REST       = Get-DockerImage "postgrest/postgrest:"
$IMG_REALTIME   = Get-DockerImage "supabase/realtime:|ecr.aws/supabase/realtime:"
$IMG_STORAGE    = Get-DockerImage "supabase/storage-api:|supabase/storage:"
$IMG_IMGPROXY   = Get-DockerImage "darthsim/imgproxy:|supabase/imgproxy:"
$IMG_META       = Get-DockerImage "supabase/postgres-meta:"
$IMG_ANALYTICS  = Get-DockerImage "supabase/logflare:|supabase/analytics:"
$IMG_EDGE       = Get-DockerImage "supabase/edge-runtime:"
$IMG_VECTOR     = Get-DockerImage "supabase/vector:|ecr.aws/supabase/vector:"
$IMG_MAILPIT    = Get-DockerImage "axllent/mailpit:|supabase/mailpit:"

# Fallbacks para imagens nao encontradas
if (-not $IMG_DB)         { $IMG_DB = "supabase/postgres:15.1.1.78" }
if (-not $IMG_STUDIO)     { $IMG_STUDIO = "supabase/studio:20240326-5e5586d" }
if (-not $IMG_KONG)       { $IMG_KONG = "kong:2.8.1" }
if (-not $IMG_GOTRUE)     { $IMG_GOTRUE = "supabase/gotrue:v2.151.0" }
if (-not $IMG_REST)       { $IMG_REST = "postgrest/postgrest:v12.2.0" }
if (-not $IMG_REALTIME)   { $IMG_REALTIME = "public.ecr.aws/supabase/realtime:v2.33.57" }
if (-not $IMG_STORAGE)    { $IMG_STORAGE = "supabase/storage-api:v0.46.4" }
if (-not $IMG_IMGPROXY)   { $IMG_IMGPROXY = "darthsim/imgproxy:v3.8.0" }
if (-not $IMG_META)       { $IMG_META = "supabase/postgres-meta:v0.83.2" }
if (-not $IMG_ANALYTICS)  { $IMG_ANALYTICS = "supabase/logflare:1.4.0" }
if (-not $IMG_EDGE)       { $IMG_EDGE = "supabase/edge-runtime:v1.58.4" }
if (-not $IMG_VECTOR)     { $IMG_VECTOR = "public.ecr.aws/supabase/vector:0.28.1-alpine" }
if (-not $IMG_MAILPIT)    { $IMG_MAILPIT = "axllent/mailpit:v1.20.5" }

# --- STEP 4: Criar docker-compose.yml ---
Write-Host "`n[4/6] Criando docker-compose-custom.yml..." -ForegroundColor Yellow

$composeContent = @"
version: '3.8'

# SUPABASE SELF-HOSTED - LCOW Fix para Windows Server 2019
# extra_hosts em cada servico forca criacao do /etc/hosts

networks:
  supabase_network:
    driver: nat
    name: supabase_network_${PROJECT_ID}

volumes:
  db_data:
  storage_data:
  functions_data:

x-extra-hosts: &extra-hosts
  extra_hosts:
    - "db:172.20.0.1"
    - "kong:172.20.0.1"
    - "localhost:127.0.0.1"

services:

  # -------------------------------------------------------
  # PostgreSQL Database
  # -------------------------------------------------------
  db:
    image: ${IMG_DB}
    platform: linux/amd64
    restart: unless-stopped
    ports:
      - "54322:5432"
    environment:
      POSTGRES_HOST: /var/run/postgresql
      PGPORT: 5432
      POSTGRES_PORT: 5432
      PGPASSWORD: ${DB_PASSWORD}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      PGDATABASE: postgres
      POSTGRES_DB: postgres
      JWT_SECRET: ${JWT_SECRET}
      JWT_EXP: 3600
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - supabase_network
    extra_hosts:
      - "localhost:127.0.0.1"
      - "kong:172.20.0.1"
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres", "-h", "localhost"]
      interval: 5s
      timeout: 5s
      retries: 10

  # -------------------------------------------------------
  # Vector (log collector)
  # -------------------------------------------------------
  vector:
    image: ${IMG_VECTOR}
    platform: linux/amd64
    restart: unless-stopped
    networks:
      - supabase_network
    extra_hosts:
      - "localhost:127.0.0.1"
      - "db:172.20.0.1"

  # -------------------------------------------------------
  # Analytics (Logflare)
  # -------------------------------------------------------
  analytics:
    image: ${IMG_ANALYTICS}
    platform: linux/amd64
    restart: unless-stopped
    ports:
      - "4000:4000"
    environment:
      LOGFLARE_NODE_HOST: 127.0.0.1
      DB_USERNAME: supabase_admin
      DB_DATABASE: _supabase
      DB_HOSTNAME: db
      DB_PORT: 5432
      DB_PASSWORD: ${DB_PASSWORD}
      DB_SCHEMA: _analytics
      LOGFLARE_API_KEY: ${SERVICE_KEY}
      LOGFLARE_SINGLE_TENANT: "true"
      LOGFLARE_SUPABASE_MODE: "true"
      LOGFLARE_MIN_CLUSTER_SIZE: 1
      RELEASE_COOKIE: cookie
    networks:
      - supabase_network
    extra_hosts:
      - "localhost:127.0.0.1"
      - "db:172.20.0.1"
    depends_on:
      db:
        condition: service_healthy

  # -------------------------------------------------------
  # Auth (GoTrue)
  # -------------------------------------------------------
  auth:
    image: ${IMG_GOTRUE}
    platform: linux/amd64
    restart: unless-stopped
    environment:
      GOTRUE_API_HOST: 0.0.0.0
      GOTRUE_API_PORT: 9999
      API_EXTERNAL_URL: http://10.140.50.10:54321
      GOTRUE_DB_DRIVER: postgres
      GOTRUE_DB_DATABASE_URL: postgres://supabase_auth_admin:${DB_PASSWORD}@db:5432/postgres
      GOTRUE_SITE_URL: http://10.140.50.10:54321
      GOTRUE_URI_ALLOW_LIST: "*"
      GOTRUE_DISABLE_SIGNUP: "false"
      GOTRUE_JWT_ADMIN_ROLES: service_role
      GOTRUE_JWT_AUD: authenticated
      GOTRUE_JWT_DEFAULT_GROUP_NAME: authenticated
      GOTRUE_JWT_EXP: 3600
      GOTRUE_JWT_SECRET: ${JWT_SECRET}
      GOTRUE_MAILER_AUTOCONFIRM: "true"
      GOTRUE_SMTP_ADMIN_EMAIL: admin@example.com
      GOTRUE_SMTP_HOST: mailpit
      GOTRUE_SMTP_PORT: 1025
      GOTRUE_SMTP_USER: ""
      GOTRUE_SMTP_PASS: ""
      GOTRUE_SMTP_SENDER_NAME: Supabase
      GOTRUE_MAILER_URLPATHS_INVITE: /auth/v1/verify
      GOTRUE_MAILER_URLPATHS_CONFIRMATION: /auth/v1/verify
      GOTRUE_MAILER_URLPATHS_RECOVERY: /auth/v1/verify
      GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE: /auth/v1/verify
      GOTRUE_EXTERNAL_PHONE_ENABLED: "false"
    networks:
      - supabase_network
    extra_hosts:
      - "localhost:127.0.0.1"
      - "db:172.20.0.1"
    depends_on:
      db:
        condition: service_healthy

  # -------------------------------------------------------
  # REST API (PostgREST)
  # -------------------------------------------------------
  rest:
    image: ${IMG_REST}
    platform: linux/amd64
    restart: unless-stopped
    environment:
      PGRST_DB_URI: postgres://authenticator:${DB_PASSWORD}@db:5432/postgres
      PGRST_DB_SCHEMAS: public,storage,graphql_public
      PGRST_DB_ANON_ROLE: anon
      PGRST_JWT_SECRET: ${JWT_SECRET}
      PGRST_DB_USE_LEGACY_GUCS: "false"
      PGRST_APP_SETTINGS_JWT_SECRET: ${JWT_SECRET}
      PGRST_APP_SETTINGS_JWT_EXP: 3600
    networks:
      - supabase_network
    extra_hosts:
      - "localhost:127.0.0.1"
      - "db:172.20.0.1"
    depends_on:
      db:
        condition: service_healthy
    command: ["postgrest"]

  # -------------------------------------------------------
  # Realtime
  # -------------------------------------------------------
  realtime:
    image: ${IMG_REALTIME}
    platform: linux/amd64
    restart: unless-stopped
    environment:
      PORT: 4000
      DB_HOST: db
      DB_PORT: 5432
      DB_USER: supabase_admin
      DB_PASSWORD: ${DB_PASSWORD}
      DB_NAME: postgres
      DB_AFTER_CONNECT_QUERY: SET search_path = _realtime
      DB_ENC_KEY: supabase_realtime_enc_key_change_me
      API_JWT_SECRET: ${JWT_SECRET}
      FLY_ALLOC_ID: fly123
      FLY_APP_NAME: realtime
      SECRET_KEY_BASE: ${JWT_SECRET}MoreCharactersToMakeItLongerForRealtime
      ERL_AFLAGS: "-proto_dist inet_tcp"
      ENABLE_TAILSCALE: "false"
      DNS_NODES: "''"
    networks:
      - supabase_network
    extra_hosts:
      - "localhost:127.0.0.1"
      - "db:172.20.0.1"
    depends_on:
      db:
        condition: service_healthy

  # -------------------------------------------------------
  # Storage
  # -------------------------------------------------------
  storage:
    image: ${IMG_STORAGE}
    platform: linux/amd64
    restart: unless-stopped
    environment:
      ANON_KEY: ${ANON_KEY}
      SERVICE_KEY: ${SERVICE_KEY}
      POSTGREST_URL: http://rest:3000
      PGRST_JWT_SECRET: ${JWT_SECRET}
      DATABASE_URL: postgres://supabase_storage_admin:${DB_PASSWORD}@db:5432/postgres
      FILE_SIZE_LIMIT: 52428800
      STORAGE_BACKEND: file
      FILE_STORAGE_BACKEND_PATH: /var/lib/storage
      TENANT_ID: ${PROJECT_ID}
      REGION: local
      GLOBAL_S3_BUCKET: stub
      GLOBAL_S3_FORCE_PATH_STYLE: "true"
      GLOBAL_S3_PROTOCOL: http
      GLOBAL_S3_ALLOW_FORWARDER_PATHS: "false"
      ENABLE_IMAGE_TRANSFORMATION: "true"
      IMGPROXY_URL: http://imgproxy:5001
    volumes:
      - storage_data:/var/lib/storage
    networks:
      - supabase_network
    extra_hosts:
      - "localhost:127.0.0.1"
      - "db:172.20.0.1"
    depends_on:
      db:
        condition: service_healthy

  # -------------------------------------------------------
  # Image Proxy
  # -------------------------------------------------------
  imgproxy:
    image: ${IMG_IMGPROXY}
    platform: linux/amd64
    restart: unless-stopped
    environment:
      IMGPROXY_BIND: ":5001"
      IMGPROXY_LOCAL_FILESYSTEM_ROOT: /
      IMGPROXY_USE_ETAG: "true"
      IMGPROXY_ENABLE_WEBP_DETECTION: "true"
    volumes:
      - storage_data:/var/lib/storage:ro
    networks:
      - supabase_network
    extra_hosts:
      - "localhost:127.0.0.1"

  # -------------------------------------------------------
  # Meta (pg-meta)
  # -------------------------------------------------------
  meta:
    image: ${IMG_META}
    platform: linux/amd64
    restart: unless-stopped
    environment:
      PG_META_PORT: 8080
      PG_META_DB_HOST: db
      PG_META_DB_PORT: 5432
      PG_META_DB_NAME: postgres
      PG_META_DB_USER: supabase_admin
      PG_META_DB_PASSWORD: ${DB_PASSWORD}
    networks:
      - supabase_network
    extra_hosts:
      - "localhost:127.0.0.1"
      - "db:172.20.0.1"
    depends_on:
      db:
        condition: service_healthy

  # -------------------------------------------------------
  # Studio (Dashboard)
  # -------------------------------------------------------
  studio:
    image: ${IMG_STUDIO}
    platform: linux/amd64
    restart: unless-stopped
    ports:
      - "54323:3000"
    environment:
      STUDIO_PG_META_URL: http://meta:8080
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      DEFAULT_ORGANIZATION_NAME: Eletronorte
      DEFAULT_PROJECT_NAME: Inspeção Torres
      SUPABASE_URL: http://kong:8000
      SUPABASE_PUBLIC_URL: http://10.140.50.10:54321
      SUPABASE_ANON_KEY: ${ANON_KEY}
      SUPABASE_SERVICE_KEY: ${SERVICE_KEY}
      AUTH_JWT_SECRET: ${JWT_SECRET}
      NEXT_TELEMETRY_DISABLED: 1
    networks:
      - supabase_network
    extra_hosts:
      - "localhost:127.0.0.1"
      - "db:172.20.0.1"
      - "kong:172.20.0.1"

  # -------------------------------------------------------
  # Kong (API Gateway) - Exposto na porta 54321
  # -------------------------------------------------------
  kong:
    image: ${IMG_KONG}
    platform: linux/amd64
    restart: unless-stopped
    ports:
      - "54321:8000"
      - "54320:8001"
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: /home/kong/kong.yml
      KONG_DNS_ORDER: LAST,A,CNAME
      KONG_PLUGINS: request-transformer,cors,key-auth,acl,basic-auth
      KONG_NGINX_PROXY_PROXY_BUFFER_SIZE: 160k
      KONG_NGINX_PROXY_PROXY_BUFFERS: 64 160k
      SUPABASE_ANON_KEY: ${ANON_KEY}
      SUPABASE_SERVICE_KEY: ${SERVICE_KEY}
      SUPABASE_DASHBOARD_USERNAME: supabase
      SUPABASE_DASHBOARD_PASSWORD: ${DB_PASSWORD}
    volumes:
      - ${PROJECT_DIR}\kong.yml:/home/kong/kong.yml:ro
    networks:
      - supabase_network
    extra_hosts:
      - "localhost:127.0.0.1"
      - "auth:172.20.0.1"
      - "rest:172.20.0.1"
      - "realtime:172.20.0.1"
      - "storage:172.20.0.1"
      - "studio:172.20.0.1"
      - "meta:172.20.0.1"
    depends_on:
      - auth
      - rest
      - realtime
      - storage

  # -------------------------------------------------------
  # Mailpit (Email testing)
  # -------------------------------------------------------
  mailpit:
    image: ${IMG_MAILPIT}
    platform: linux/amd64
    restart: unless-stopped
    ports:
      - "54324:8025"
    networks:
      - supabase_network
    extra_hosts:
      - "localhost:127.0.0.1"
"@

Set-Content -Path $COMPOSE_OUT -Value $composeContent -Encoding UTF8
Write-Host "  Compose criado em: $COMPOSE_OUT" -ForegroundColor Green

# --- STEP 5: Criar kong.yml ---
Write-Host "`n[5/6] Criando kong.yml..." -ForegroundColor Yellow

$kongContent = @"
_format_version: '2.1'
_transform: true

consumers:
  - username: anon
    keyauth_credentials:
      - key: ${ANON_KEY}
  - username: service_role
    keyauth_credentials:
      - key: ${SERVICE_KEY}

acls:
  - consumer: anon
    group: anon
  - consumer: service_role
    group: admin

services:
  - name: auth-v1-open
    url: http://auth:9999/verify
    routes:
      - name: auth-v1-open
        strip_path: true
        paths:
          - /auth/v1/verify
    plugins:
      - name: cors

  - name: auth-v1-open-callback
    url: http://auth:9999/callback
    routes:
      - name: auth-v1-open-callback
        strip_path: true
        paths:
          - /auth/v1/callback
    plugins:
      - name: cors

  - name: auth-v1
    url: http://auth:9999/
    routes:
      - name: auth-v1-all
        strip_path: true
        paths:
          - /auth/v1/
    plugins:
      - name: cors
      - name: key-auth
        config:
          hide_credentials: false
      - name: acl
        config:
          hide_groups_header: true
          allow:
            - admin
            - anon

  - name: rest-v1
    url: http://rest:3000/
    routes:
      - name: rest-v1-all
        strip_path: true
        paths:
          - /rest/v1/
    plugins:
      - name: cors
      - name: key-auth
        config:
          hide_credentials: true
      - name: acl
        config:
          hide_groups_header: true
          allow:
            - admin
            - anon

  - name: realtime-v1
    url: http://realtime:4000/socket/
    routes:
      - name: realtime-v1-all
        strip_path: true
        paths:
          - /realtime/v1/
    plugins:
      - name: cors
      - name: key-auth
        config:
          hide_credentials: false
      - name: acl
        config:
          hide_groups_header: true
          allow:
            - admin
            - anon

  - name: storage-v1
    url: http://storage:5000/
    routes:
      - name: storage-v1-all
        strip_path: true
        paths:
          - /storage/v1/
    plugins:
      - name: cors
      - name: key-auth
        config:
          hide_credentials: true
      - name: acl
        config:
          hide_groups_header: true
          allow:
            - admin
            - anon

  - name: meta
    url: http://meta:8080/
    routes:
      - name: meta-all
        strip_path: true
        paths:
          - /pg/
    plugins:
      - name: key-auth
        config:
          hide_credentials: false
      - name: acl
        config:
          hide_groups_header: true
          allow:
            - admin
"@

Set-Content -Path "$PROJECT_DIR\kong.yml" -Value $kongContent -Encoding UTF8
Write-Host "  kong.yml criado em: $PROJECT_DIR\kong.yml" -ForegroundColor Green

# --- STEP 6: Subir o stack ---
Write-Host "`n[6/6] Subindo o stack..." -ForegroundColor Yellow

# Pre-criar a rede NAT
$netName = "supabase_network_${PROJECT_ID}"
docker network rm $netName 2>$null
docker network create --driver=nat $netName 2>$null
Write-Host "  Rede '$netName' criada (driver: nat)" -ForegroundColor Green

# Subir os containers
Write-Host "`n  Iniciando containers (aguarde ate 2 minutos)..." -ForegroundColor Cyan
Set-Location $PROJECT_DIR
docker compose -f $COMPOSE_OUT up -d

Write-Host "`n======================================================" -ForegroundColor Cyan
Write-Host " VERIFICANDO STATUS..." -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Start-Sleep 15
docker compose -f $COMPOSE_OUT ps

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host " SUPABASE ENDPOINTS:" -ForegroundColor Green
Write-Host "   API URL : http://10.140.50.10:54321" -ForegroundColor White
Write-Host "   Studio  : http://10.140.50.10:54323" -ForegroundColor White
Write-Host "   Database: 10.140.50.10:54322" -ForegroundColor White
Write-Host ""
Write-Host "   Anon Key (primeiros 50 chars):" -ForegroundColor Yellow
Write-Host "   $($ANON_KEY.Substring(0, 50))..." -ForegroundColor White
Write-Host ""
Write-Host "   Service Key (primeiros 50 chars):" -ForegroundColor Yellow
Write-Host "   $($SERVICE_KEY.Substring(0, 50))..." -ForegroundColor White
Write-Host "======================================================" -ForegroundColor Green
