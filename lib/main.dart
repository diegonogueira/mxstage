import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/screens/connect_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const MxStageApp());
}

class MxStageApp extends StatelessWidget {
  const MxStageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mxstage',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        cardColor: const Color(0xFF1A1A1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111111),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: Colors.tealAccent,
          inactiveTrackColor: Color(0xFF2A2A2A),
          thumbColor: Colors.white,
          trackHeight: 4,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF1A1A1A),
          border: OutlineInputBorder(),
        ),
      ),
      home: const ConnectScreen(),
    );
  }
}
