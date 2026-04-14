# =============================================================
# EXECUTE ESTE SCRIPT NO SERVIDOR 10.140.50.10
# Abre o PowerShell como Admin no servidor e cole este script
# =============================================================

Write-Host "=== DEPLOY NO SERVIDOR ===" -ForegroundColor Cyan

# --- 1. Verificar Docker ---
Write-Host "`n[1/4] Verificando Docker..." -ForegroundColor Yellow
$dockerOk = (docker info 2>$null) -ne $null
if (-not $dockerOk) { 
    Write-Host "ERRO: Docker nao esta rodando!" -ForegroundColor Red
    exit 1
}
Write-Host "  Docker OK" -ForegroundColor Green

# --- 2. Verificar/subir Supabase ---
Write-Host "`n[2/4] Verificando Supabase..." -ForegroundColor Yellow
$containers = docker ps --format "{{.Names}}" 2>$null
if ($containers -match "supabase_kong") {
    Write-Host "  Supabase ja esta rodando!" -ForegroundColor Green
    docker ps --format "table {{.Names}}`t{{.Status}}" | Select-String "supabase"
} else {
    Write-Host "  Supabase nao esta rodando. Iniciando..." -ForegroundColor Yellow
    
    $deployScript = "C:\aplicativos\fotos_h_supabase\deploy_run.ps1"
    if (Test-Path $deployScript) {
        Write-Host "  Executando $deployScript..." -ForegroundColor DarkYellow
        & $deployScript
    } else {
        Write-Host "  Script deploy_run.ps1 nao encontrado em $deployScript" -ForegroundColor Red
        Write-Host "  Copie o arquivo supabase_deploy\deploy_run.ps1 do seu PC para C:\aplicativos\fotos_h_supabase\" -ForegroundColor Yellow
    }
}

# --- 3. Copiar build web ---
Write-Host "`n[3/4] Verificando build web..." -ForegroundColor Yellow

# Procurar o ZIP do build nos discos redirecionados pelo RDP
$rdpDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match "^[D-Z]:\\" }
Write-Host "  Discos visiveis (incluindo RDP): $($rdpDrives.Name -join ', ')"

$zipFound = $null
foreach ($drive in $rdpDrives) {
    $zipPath = Join-Path $drive.Root "fotos_h_build.zip"
    if (Test-Path $zipPath) { $zipFound = $zipPath; break }
    # Tentar no Temp do usuario
    $zipPath2 = "\\tsclient\C\Users\jpfilho\AppData\Local\Temp\fotos_h_build.zip"
    if (Test-Path $zipPath2) { $zipFound = $zipPath2; break }
}

# Tentar via tsclient (RDP drive redirect)
if (-not $zipFound) {
    $tsclient = "\\tsclient\C\Users\jpfilho\AppData\Local\Temp\fotos_h_build.zip"
    if (Test-Path $tsclient) { $zipFound = $tsclient }
}

if ($zipFound) {
    Write-Host "  ZIP encontrado: $zipFound" -ForegroundColor Green
    $DEST = "C:\inetpub\wwwroot\fotos_h"
    New-Item -ItemType Directory -Path $DEST -Force | Out-Null
    Expand-Archive -Path $zipFound -DestinationPath $DEST -Force
    Write-Host "  Build extraido em: $DEST" -ForegroundColor Green
} else {
    Write-Host "  ZIP nao encontrado automaticamente." -ForegroundColor Yellow
    Write-Host "  Copie manualmente de: \\tsclient\C\Users\jpfilho\AppData\Local\Temp\fotos_h_build.zip" -ForegroundColor Cyan
    Write-Host "  Para: C:\inetpub\wwwroot\fotos_h\" -ForegroundColor Cyan
    
    # Tentar copiar direto via tsclient
    Write-Host "`n  Tentando copy via tsclient..." -ForegroundColor DarkYellow
    try {
        $src = "\\tsclient\C\Users\jpfilho\AppData\Local\Temp\fotos_h_build.zip"
        Copy-Item $src "C:\fotos_h_build.zip" -Force
        Expand-Archive "C:\fotos_h_build.zip" -DestinationPath "C:\inetpub\wwwroot\fotos_h" -Force
        Write-Host "  COPIADO E EXTRAIDO!" -ForegroundColor Green
    } catch {
        Write-Host "  Falhou: $_" -ForegroundColor Red
    }
}

# --- 4. Verificar IIS / servidor web ---
Write-Host "`n[4/4] Verificando IIS..." -ForegroundColor Yellow
$iis = Get-Service W3SVC -ErrorAction SilentlyContinue
if ($iis) {
    if ($iis.Status -ne "Running") { Start-Service W3SVC }
    Write-Host "  IIS rodando!" -ForegroundColor Green
    
    # Verificar se o site esta configurado
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $site = Get-Website | Where-Object { $_.physicalPath -like "*fotos_h*" }
    if (-not $site) {
        Write-Host "  ATENCAO: Nenhum site IIS aponta para fotos_h" -ForegroundColor Yellow
        Write-Host "  Configure manualmente no IIS Manager ou execute:" -ForegroundColor Yellow
        Write-Host '  New-WebSite -Name "fotos_h" -PhysicalPath "C:\inetpub\wwwroot\fotos_h" -Port 80 -Force' -ForegroundColor Cyan
    }
} else {
    Write-Host "  IIS nao encontrado. Verifique o servidor web configurado." -ForegroundColor Yellow
}

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host " STATUS FINAL" -ForegroundColor Green
Write-Host "  Supabase API : http://10.140.50.10:54321" -ForegroundColor White
Write-Host "  Supabase UI  : http://10.140.50.10:54323" -ForegroundColor White
Write-Host "  App Web      : http://10.140.50.10 (verifique porta do IIS)" -ForegroundColor White
Write-Host "======================================================" -ForegroundColor Green
