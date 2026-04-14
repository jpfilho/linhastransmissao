@echo off
color 0B
echo ========================================================
echo INICIANDO O APLICATIVO WEB...
echo ========================================================
set FLUTTER_ROOT=C:\src\flutter
set PATH=C:\src\flutter\bin;C:\Program Files\Git\cmd;%PATH%

cd /d "C:\aplicativos\Projetos_Source\fotos_h_app"

taskkill /F /IM dart.exe >nul 2>&1
del /f /q "C:\src\flutter\bin\cache\lockfile" >nul 2>&1

echo O servidor esta ligando na porta 8085...
echo ========================================================
echo MINIMIZE ESTA JANELA ! NAO CANCELE! 
echo DEIXE ESTA JANELA ABERTA NO FUNDO PARA O SISTEMA FUNCIONAR!
echo ========================================================
echo Abra o seu navegador e acesse: http://localhost:8085

call flutter run -d web-server --web-port 8085
