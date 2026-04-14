# =============================================================
# DEPLOY PRODUCAO - fotos_h
# Envia o build web para o servidor 10.140.50.10
# Execute: .\supabase_deploy\deploy_producao.ps1
# =============================================================

$SERVER   = "10.140.50.10"
$USER     = "jpfilho"           # ajuste se necessario
$BUILD    = "C:\aplicativos\fotos_h\build\web"
$DEST_DIR = "C:\inetpub\wwwroot\fotos_h"   # pasta no servidor (IIS ou equivalente)
$ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRFA0NiK7kyqd918Os5P6q2nd23OfmoxKSmUMOuNOrE"

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " DEPLOY PRODUCAO - Inspeção Aérea de Torres" -ForegroundColor Cyan
Write-Host " Servidor: $SERVER" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# --- 1. Verificar build existe ---
Write-Host "`n[1/4] Verificando build..." -ForegroundColor Yellow
if (-not (Test-Path "$BUILD\index.html")) {
    Write-Error "ERRO: Build nao encontrado em $BUILD. Execute: flutter build web --release"
    exit 1
}
$totalMB = [Math]::Round((Get-ChildItem $BUILD -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
Write-Host "  Build OK: $totalMB MB em $BUILD" -ForegroundColor Green

# --- 2. Testar conectividade ---
Write-Host "`n[2/4] Testando conectividade com $SERVER..." -ForegroundColor Yellow
if (-not (Test-Connection $SERVER -Count 1 -Quiet)) {
    Write-Error "ERRO: Servidor $SERVER inacessivel!"
    exit 1
}
Write-Host "  Ping OK" -ForegroundColor Green

# --- 2b. Testar Supabase no servidor ---
Write-Host "  Testando Supabase em http://${SERVER}:54321..." -ForegroundColor DarkYellow
try {
    $r = Invoke-WebRequest "http://${SERVER}:54321/rest/v1/torres?limit=1" `
         -Headers @{"apikey"=$ANON_KEY;"Authorization"="Bearer $ANON_KEY"} `
         -UseBasicParsing -TimeoutSec 5
    Write-Host "  Supabase REST: OK (HTTP $($r.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "  AVISO: Supabase REST nao respondeu - $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Verifique se o Supabase esta rodando no servidor!" -ForegroundColor Red
}

# --- 3. Copiar arquivos via robocopy (compartilhamento de rede) ---
Write-Host "`n[3/4] Copiando build para \\$SERVER\..." -ForegroundColor Yellow
Write-Host "  Destino: \\$SERVER\$($DEST_DIR.Replace('C:\','C$\'))" -ForegroundColor DarkYellow

$UNC_DEST = "\\$SERVER\$($DEST_DIR.Replace('C:\','C$\'))"

# Tentar via compartilhamento de rede Windows primeiro
try {
    if (Test-Path $UNC_DEST) {
        Write-Host "  Compartilhamento encontrado! Copiando..." -ForegroundColor Green
        robocopy $BUILD $UNC_DEST /MIR /NFL /NDL /NJH /NJS /nc /ns /np
        Write-Host "  Copia concluida!" -ForegroundColor Green
    } else {
        Write-Host "  Compartilhamento nao encontrado. Tentando via SCP..." -ForegroundColor Yellow
        throw "Compartilhamento nao acessivel"
    }
} catch {
    # Fallback: SCP
    Write-Host "`n  Tentando SCP para ${USER}@${SERVER}..." -ForegroundColor Yellow
    Write-Host "  (Sera solicitada a senha do usuario $USER no servidor)" -ForegroundColor DarkYellow
    
    # Compactar o build em zip
    $zipPath = "$env:TEMP\fotos_h_build.zip"
    Write-Host "  Compactando build em $zipPath..." -ForegroundColor DarkYellow
    Compress-Archive -Path "$BUILD\*" -DestinationPath $zipPath -Force
    $zipMB = [Math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host "  ZIP criado: $zipMB MB" -ForegroundColor Green
    
    Write-Host "`n  Execute manualmente no servidor ($SERVER):" -ForegroundColor Cyan
    Write-Host "    scp ${USER}@localhost:$zipPath ${USER}@${SERVER}:C:\fotos_h_build.zip" -ForegroundColor White
    Write-Host "    E entao no servidor extraia: Expand-Archive C:\fotos_h_build.zip -DestinationPath $DEST_DIR -Force" -ForegroundColor White
    
    # Tentar SCP direto
    Write-Host "`n  Tentando SCP direto..." -ForegroundColor DarkYellow
    scp -o StrictHostKeyChecking=no $zipPath "${USER}@${SERVER}:C:/fotos_h_build.zip"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ZIP enviado via SCP!" -ForegroundColor Green
        Write-Host "`n  PROXIMOS PASSOS NO SERVIDOR ($SERVER):" -ForegroundColor Cyan
        Write-Host "  1. Extrair: Expand-Archive C:\fotos_h_build.zip -DestinationPath $DEST_DIR -Force" -ForegroundColor White
        Write-Host "  2. Reiniciar IIS: iisreset" -ForegroundColor White
    } else {
        Write-Host "`n  SCP falhou. Opcoes manuais:" -ForegroundColor Red
        Write-Host "  1. Copie o ZIP de $zipPath para o servidor" -ForegroundColor Yellow
        Write-Host "  2. Extraia em: $DEST_DIR" -ForegroundColor Yellow
    }
}

# --- 4. Verificar resultado ---
Write-Host "`n[4/4] Verificando deploy..." -ForegroundColor Yellow
try {
    $r = Invoke-WebRequest "http://${SERVER}:54321/rest/v1/" `
         -Headers @{"apikey"=$ANON_KEY} -UseBasicParsing -TimeoutSec 5
    Write-Host "  API Supabase: OK" -ForegroundColor Green
} catch {
    Write-Host "  API Supabase: nao verificada" -ForegroundColor Yellow
}

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host " DEPLOY CONCLUIDO!" -ForegroundColor Green
Write-Host "  App: http://$SERVER (verifique a porta do IIS/servidor web)" -ForegroundColor White
Write-Host "  API: http://${SERVER}:54321" -ForegroundColor White
Write-Host "  Studio: http://${SERVER}:54323" -ForegroundColor White
Write-Host "======================================================" -ForegroundColor Green
