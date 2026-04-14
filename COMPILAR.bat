@echo off
color 0A
echo ========================================================
echo INICIANDO COMPILADOR FLUTTER DO SERVIDOR
echo ========================================================

cd /d "C:\aplicativos\Projetos_Source\fotos_h_app"
set PATH=C:\src\flutter\bin;C:\Program Files\Git\cmd;%PATH%

echo Destravando processos antigos...
taskkill /F /IM dart.exe >nul 2>&1
del /f /q "C:\src\flutter\bin\cache\lockfile" >nul 2>&1

echo Limpando cache antigo (para forcar o robo a usar o codigo novo)...
rmdir /s /q "build\web" >nul 2>&1

echo Compilando projeto para Web agora... (Isso pode demorar 1 minuto)
call flutter build web

if exist "build\web\index.html" (
    echo ========================================================
    echo COMPILACAO CONCLUIDA COM SUCESSO!
    echo Copiando os arquivos para a Producao www...
    xcopy /Y /S /E "build\web\*" "C:\aplicativos\fotos_h\www\"
    echo ========================================================
    echo DEPLOY FINALIZADO! Pode iniciar seu python para testar!
) else (
    echo ========================================================
    echo ERRO. O Flutter nao conseguiu compilar o codigo fonte.
    echo ========================================================
)
pause
