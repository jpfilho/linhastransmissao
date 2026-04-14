@echo off
set FLUTTER_ROOT=C:\src\flutter
set PATH=C:\src\flutter\bin;C:\Program Files\Git\cmd;%PATH%
cd /d "C:\aplicativos\Projetos_Source\fotos_h_app"
call flutter test test\wipe_test.dart
