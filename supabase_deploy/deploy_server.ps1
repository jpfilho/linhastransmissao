# =============================================================
# EXECUTE ESTE SCRIPT NO SERVIDOR 10.140.50.10
# Cria todos os arquivos necessários e sobe o Supabase
# =============================================================

$DEPLOY_DIR = "C:\aplicativos\fotos_h_supabase"
New-Item -ItemType Directory -Path $DEPLOY_DIR -Force | Out-Null
Set-Location $DEPLOY_DIR

Write-Host "=== Criando arquivos de configuracao ===" -ForegroundColor Cyan

# -------------------------------------------------------
# Criar .env
# -------------------------------------------------------
@"
POSTGRES_PASSWORD=postgres
JWT_SECRET=super-secret-jwt-token-with-at-least-32-characters-long
ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRFA0NiK7kyqd918Os5P6q2nd23OfmoxKSmUMOuNOrE
SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hj04zWl196z2-SBc0
DASHBOARD_USERNAME=supabase
DASHBOARD_PASSWORD=admin1234
PROJECT_ID=fotos_h_supabase
API_EXTERNAL_URL=http://10.140.50.10:54321
SITE_URL=http://10.140.50.10:54321
ADDITIONAL_REDIRECT_URLS=
DISABLE_SIGNUP=false
"@ | Set-Content ".env" -Encoding UTF8
Write-Host "  .env criado" -ForegroundColor Green

# -------------------------------------------------------
# Criar kong.yml
# -------------------------------------------------------
@'
_format_version: '2.1'
_transform: true

consumers:
  - username: anon
    keyauth_credentials:
      - key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRFA0NiK7kyqd918Os5P6q2nd23OfmoxKSmUMOuNOrE
  - username: service_role
    keyauth_credentials:
      - key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hj04zWl196z2-SBc0

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
'@ | Set-Content "kong.yml" -Encoding UTF8
Write-Host "  kong.yml criado" -ForegroundColor Green

# -------------------------------------------------------
# Criar docker-compose.yml
# -------------------------------------------------------
@'
version: '3.8'

networks:
  supabase_net:
    driver: nat
    name: supabase_network_fotos_h_supabase

volumes:
  db_data:
    name: supabase_db_fotos_h_supabase
  storage_data:
    name: supabase_storage_fotos_h_supabase

services:

  db:
    image: public.ecr.aws/supabase/postgres:17.6.1.066
    platform: linux/amd64
    restart: unless-stopped
    ports:
      - "54322:5432"
    environment:
      POSTGRES_HOST: /var/run/postgresql
      PGPORT: 5432
      POSTGRES_PORT: 5432
      PGPASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      PGDATABASE: postgres
      POSTGRES_DB: postgres
      JWT_SECRET: ${JWT_SECRET}
      JWT_EXP: 3600
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - supabase_net
    extra_hosts:
      - "host.docker.internal:10.140.50.10"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -h localhost -p 5432"]
      interval: 10s
      timeout: 5s
      retries: 15
      start_period: 30s

  vector:
    image: public.ecr.aws/supabase/vector:0.28.1-alpine
    platform: linux/amd64
    restart: unless-stopped
    networks:
      - supabase_net
    extra_hosts:
      - "host.docker.internal:10.140.50.10"
    depends_on:
      db:
        condition: service_healthy

  auth:
    image: public.ecr.aws/supabase/gotrue:v2.184.0
    platform: linux/amd64
    restart: unless-stopped
    environment:
      GOTRUE_API_HOST: 0.0.0.0
      GOTRUE_API_PORT: 9999
      API_EXTERNAL_URL: ${API_EXTERNAL_URL}
      GOTRUE_DB_DRIVER: postgres
      GOTRUE_DB_DATABASE_URL: postgres://supabase_auth_admin:${POSTGRES_PASSWORD}@db:5432/postgres
      GOTRUE_SITE_URL: ${SITE_URL}
      GOTRUE_URI_ALLOW_LIST: ${ADDITIONAL_REDIRECT_URLS}
      GOTRUE_DISABLE_SIGNUP: ${DISABLE_SIGNUP}
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
      - supabase_net
    extra_hosts:
      - "host.docker.internal:10.140.50.10"
    depends_on:
      db:
        condition: service_healthy

  rest:
    image: public.ecr.aws/supabase/postgrest:v14.1
    platform: linux/amd64
    restart: unless-stopped
    environment:
      PGRST_DB_URI: postgres://authenticator:${POSTGRES_PASSWORD}@db:5432/postgres
      PGRST_DB_SCHEMAS: public,storage,graphql_public
      PGRST_DB_ANON_ROLE: anon
      PGRST_JWT_SECRET: ${JWT_SECRET}
      PGRST_DB_USE_LEGACY_GUCS: "false"
      PGRST_APP_SETTINGS_JWT_SECRET: ${JWT_SECRET}
      PGRST_APP_SETTINGS_JWT_EXP: 3600
    networks:
      - supabase_net
    extra_hosts:
      - "host.docker.internal:10.140.50.10"
    depends_on:
      db:
        condition: service_healthy
    command: ["postgrest"]

  realtime:
    image: public.ecr.aws/supabase/realtime:v2.33.57
    platform: linux/amd64
    restart: unless-stopped
    environment:
      PORT: 4000
      DB_HOST: db
      DB_PORT: 5432
      DB_USER: supabase_admin
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_NAME: postgres
      DB_AFTER_CONNECT_QUERY: SET search_path = _realtime
      DB_ENC_KEY: supabaseEncryptedKeyForLocalDev00001
      API_JWT_SECRET: ${JWT_SECRET}
      FLY_ALLOC_ID: fly123
      FLY_APP_NAME: realtime
      SECRET_KEY_BASE: UpNVntn3cDxHJpq99YMc1T1AQgQpc8kfYTuRgBiYa15BLrx8etQoXz3gZv1/u2oq
      ERL_AFLAGS: "-proto_dist inet_tcp"
      ENABLE_TAILSCALE: "false"
      DNS_NODES: "''"
      RLIMIT_NOFILE: "10000"
    networks:
      - supabase_net
    extra_hosts:
      - "host.docker.internal:10.140.50.10"
    depends_on:
      db:
        condition: service_healthy

  storage:
    image: public.ecr.aws/supabase/storage-api:v1.33.1
    platform: linux/amd64
    restart: unless-stopped
    environment:
      ANON_KEY: ${ANON_KEY}
      SERVICE_KEY: ${SERVICE_ROLE_KEY}
      POSTGREST_URL: http://rest:3000
      PGRST_JWT_SECRET: ${JWT_SECRET}
      DATABASE_URL: postgres://supabase_storage_admin:${POSTGRES_PASSWORD}@db:5432/postgres
      FILE_SIZE_LIMIT: 52428800
      STORAGE_BACKEND: file
      FILE_STORAGE_BACKEND_PATH: /var/lib/storage
      TENANT_ID: ${PROJECT_ID}
      REGION: local
      GLOBAL_S3_BUCKET: stub
      GLOBAL_S3_FORCE_PATH_STYLE: "true"
      GLOBAL_S3_PROTOCOL: http
      ENABLE_IMAGE_TRANSFORMATION: "true"
      IMGPROXY_URL: http://imgproxy:5001
    volumes:
      - storage_data:/var/lib/storage
    networks:
      - supabase_net
    extra_hosts:
      - "host.docker.internal:10.140.50.10"
    depends_on:
      db:
        condition: service_healthy

  imgproxy:
    image: public.ecr.aws/supabase/imgproxy:v3.8.0
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
      - supabase_net
    extra_hosts:
      - "host.docker.internal:10.140.50.10"

  meta:
    image: public.ecr.aws/supabase/postgres-meta:v0.95.1
    platform: linux/amd64
    restart: unless-stopped
    environment:
      PG_META_PORT: 8080
      PG_META_DB_HOST: db
      PG_META_DB_PORT: 5432
      PG_META_DB_NAME: postgres
      PG_META_DB_USER: supabase_admin
      PG_META_DB_PASSWORD: ${POSTGRES_PASSWORD}
    networks:
      - supabase_net
    extra_hosts:
      - "host.docker.internal:10.140.50.10"
    depends_on:
      db:
        condition: service_healthy

  studio:
    image: public.ecr.aws/supabase/studio:2025.12.17-sha-43f4f7f
    platform: linux/amd64
    restart: unless-stopped
    ports:
      - "54323:3000"
    environment:
      STUDIO_PG_META_URL: http://meta:8080
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      DEFAULT_ORGANIZATION_NAME: Eletronorte
      DEFAULT_PROJECT_NAME: Inspecao Torres
      SUPABASE_URL: http://kong:8000
      SUPABASE_PUBLIC_URL: ${API_EXTERNAL_URL}
      SUPABASE_ANON_KEY: ${ANON_KEY}
      SUPABASE_SERVICE_KEY: ${SERVICE_ROLE_KEY}
      AUTH_JWT_SECRET: ${JWT_SECRET}
      NEXT_TELEMETRY_DISABLED: 1
    networks:
      - supabase_net
    extra_hosts:
      - "host.docker.internal:10.140.50.10"
    depends_on:
      - auth
      - rest

  kong:
    image: public.ecr.aws/supabase/kong:2.8.1
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
      SUPABASE_SERVICE_KEY: ${SERVICE_ROLE_KEY}
      DASHBOARD_USERNAME: ${DASHBOARD_USERNAME}
      DASHBOARD_PASSWORD: ${DASHBOARD_PASSWORD}
    volumes:
      - type: bind
        source: ./kong.yml
        target: /home/kong/kong.yml
        read_only: true
    networks:
      - supabase_net
    extra_hosts:
      - "host.docker.internal:10.140.50.10"
    depends_on:
      - auth
      - rest
      - realtime
      - storage

  mailpit:
    image: public.ecr.aws/supabase/mailpit:v1.22.3
    platform: linux/amd64
    restart: unless-stopped
    ports:
      - "54324:8025"
    networks:
      - supabase_net
    extra_hosts:
      - "host.docker.internal:10.140.50.10"
'@ | Set-Content "docker-compose.yml" -Encoding UTF8
Write-Host "  docker-compose.yml criado" -ForegroundColor Green

# -------------------------------------------------------
# Pre-criar rede NAT e iniciar
# -------------------------------------------------------
Write-Host "`n=== Preparando rede Docker ===" -ForegroundColor Cyan
docker network rm supabase_network_fotos_h_supabase 2>$null
docker network create --driver=nat supabase_network_fotos_h_supabase 2>$null | Out-Null
Write-Host "  Rede NAT criada" -ForegroundColor Green

Write-Host "`n=== Iniciando Supabase Stack ===" -ForegroundColor Cyan
Write-Host "  (aguarde 2-3 minutos para todos os servicos subirem)`n"
docker compose --env-file .env up -d

Write-Host "`n=== Aguardando estabilizacao (30s)... ===" -ForegroundColor Yellow
Start-Sleep 30

Write-Host "`n=== Status dos containers ===" -ForegroundColor Cyan
docker compose ps

Write-Host "`n=== ENDPOINTS ===" -ForegroundColor Green
Write-Host "  API + Auth + Storage : http://10.140.50.10:54321" -ForegroundColor White
Write-Host "  Studio (Dashboard)   : http://10.140.50.10:54323" -ForegroundColor White
Write-Host "  Database (externo)   : 10.140.50.10:54322" -ForegroundColor White
Write-Host "  Email (mailpit)      : http://10.140.50.10:54324" -ForegroundColor White
Write-Host ""
Write-Host "  ANON KEY:" -ForegroundColor Yellow
Write-Host "  eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRFA0NiK7kyqd918Os5P6q2nd23OfmoxKSmUMOuNOrE"
