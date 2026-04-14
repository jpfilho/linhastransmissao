@echo off
color 0B
echo ========================================================
echo SOLUCIONANDO PROBLEMAS DO SUPABASE...
echo ========================================================
echo.
cd /d "C:\aplicativos\fotos_h_supabase"
echo Parando os containeres (pode demorar alguns segundos)...
call supabase stop
echo.
echo Iniciando os containeres...
call supabase start
echo.
echo ========================================================
echo Feito! Pode verificar seus buckets agora.
echo ========================================================
pause
