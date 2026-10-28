import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_config.dart';
import 'core/theme.dart';
import 'splash_screen.dart';
import 'services/database_service.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  // Single place to catch anything that escapes widget/async error handling.
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[FlutterError] ${details.exceptionAsString()}');
    };

    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    await SettingsService.load();
    await DatabaseService.init();

    runApp(const FaceAuthApp());
  }, (error, stack) {
    debugPrint('[Uncaught] $error\n$stack');
  });
}

class FaceAuthApp extends StatelessWidget {
  const FaceAuthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
    );
  }
}
