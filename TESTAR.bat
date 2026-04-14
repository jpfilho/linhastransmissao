@echo off
color 0B
echo ========================================================
echo INICIANDO MODO DE TESTE (HOT RELOAD)
echo ========================================================
set FLUTTER_ROOT=C:\src\flutter
set PATH=C:\src\flutter\bin;C:\Program Files\Git\cmd;%PATH%

cd /d "C:\aplicativos\Projetos_Source\fotos_h_app"

echo Destravando arquivos...
taskkill /F /IM dart.exe >nul 2>&1
del /f /q "C:\src\flutter\bin\cache\lockfile" >nul 2>&1

echo Iniciando servidor web de testes...
echo Abra o seu navegador e acesse: http://localhost:8085
echo.
echo Para sair, aperte 'q' ou feche esta janela.
echo ========================================================

call flutter run -d web-server --web-port 8085
