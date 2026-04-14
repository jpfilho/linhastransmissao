#!/bin/bash
# ============================================================
#  DEPLOY COMPLETO - Sistema de Inspecao de Torres
#  Execute este script na raiz da sua VPS como root
#  Uso: bash deploy_vps.sh <IP_DA_VPS>
# ============================================================
set -e

VPS_IP="${1:-SEU_IP_AQUI}"
APP_DIR="/var/www/fotos_h"
FLUTTER_DIR="/opt/flutter"
REPO_URL="https://github.com/jpfilho/linhastransmissao.git"

echo "======================================================"
echo "  PASSO 1: Atualizando sistema e instalando dependencias"
echo "======================================================"
apt-get update -y
apt-get install -y git curl unzip nginx snapd

echo "======================================================"
echo "  PASSO 2: Instalando Flutter"
echo "======================================================"
if [ ! -d "$FLUTTER_DIR" ]; then
  git clone https://github.com/flutter/flutter.git "$FLUTTER_DIR" --branch stable --single-branch
fi
export PATH="$FLUTTER_DIR/bin:$PATH"
flutter doctor --android-licenses || true
flutter config --enable-web

echo "======================================================"
echo "  PASSO 3: Clonando o repositório do projeto"
echo "======================================================"
rm -rf "$APP_DIR/source"
mkdir -p "$APP_DIR/source"
git clone "$REPO_URL" "$APP_DIR/source"
cd "$APP_DIR/source"

echo "======================================================"
echo "  PASSO 4: Atualizando config para apontar para nova VPS"
echo "======================================================"
# Substitui a URL do Supabase pela URL da nova VPS
sed -i "s|http://10.140.50.10:54321|http://$VPS_IP:8000|g" \
  lib/core/config/app_constants.dart

echo "======================================================"
echo "  PASSO 5: Compilando o aplicativo Flutter para Web"
echo "======================================================"
export PATH="$FLUTTER_DIR/bin:$PATH"
flutter pub get
flutter build web --release

echo "======================================================"
echo "  PASSO 6: Publicando no Nginx"
echo "======================================================"
rm -rf "$APP_DIR/www"
cp -r "$APP_DIR/source/build/web" "$APP_DIR/www"

# Configura o Nginx
cat > /etc/nginx/sites-available/fotos_h << EOF
server {
    listen 80;
    server_name $VPS_IP;

    root $APP_DIR/www;
    index index.html;

    # Flutter web - todas as rotas vão para index.html
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Cache de assets estáticos
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf)$ {
        expires 1y;
        add_header Cache-Control "public";
    }
}
EOF

ln -sf /etc/nginx/sites-available/fotos_h /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo "======================================================"
echo "  PASSO 7: Aplicando migracoes no Supabase da nova VPS"
echo "======================================================"
echo "  -> Aguardando o Supabase estar pronto..."

# Espera o Postgres do Supabase subir (porta 5432)
for i in {1..30}; do
    nc -z localhost 5432 && break || sleep 5
    echo "   Tentativa $i/30..."
done

# Aplica as migrations na ordem
for f in "$APP_DIR/source/supabase_migrations_backup/"*.sql; do
    echo "  -> Aplicando: $(basename $f)"
    PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d postgres -f "$f" || true
done

echo ""
echo "======================================================"
echo "  ✅ DEPLOY CONCLUÍDO!"
echo "======================================================"
echo "  App Flutter Web: http://$VPS_IP"
echo "  Supabase Studio: http://$VPS_IP:8000"
echo "  Supabase API:    http://$VPS_IP:8000"
echo "======================================================"
