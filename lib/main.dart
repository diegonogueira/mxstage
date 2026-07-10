import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ignore: unused_import

import 'ui/palette.dart';
import 'ui/screens/connect_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Allow both portrait and landscape — layout adapts via MediaQuery
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MxWiseApp());
}

class MxWiseApp extends StatelessWidget {
  const MxWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MXWise',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.blue,
          brightness: Brightness.dark,
          surface: AppColors.canvas,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.canvas,
        cardColor: AppColors.panel,
        cardTheme: const CardThemeData(color: AppColors.panel, elevation: 0),
        dividerColor: AppColors.border,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.panel,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: AppColors.blue,
          inactiveTrackColor: AppColors.track,
          thumbColor: Colors.white,
          trackHeight: 6,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: AppColors.panel,
          border: OutlineInputBorder(),
        ),
      ),
      home: const ConnectScreen(),
    );
  }
}
