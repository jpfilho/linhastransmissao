import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/config/routes.dart';

class InspecaoAereaApp extends StatelessWidget {
  const InspecaoAereaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Inspeção Aérea de Torres',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: appRouter,
    );
  }
}
