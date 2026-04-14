import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_skill/flutter_skill.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/config/app_constants.dart';

void main() async {
  if (kDebugMode) FlutterSkillBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Inicializar Supabase
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  runApp(
    const ProviderScope(
      child: InspecaoAereaApp(),
    ),
  );
}
