import 'package:flutter/material.dart';
import 'screens/map_screen.dart';

void main() {
  runApp(const RekkerJegFerjaApp());
}

class RekkerJegFerjaApp extends StatelessWidget {
  const RekkerJegFerjaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rekker jeg ferga?',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.dark),
      home: const MapScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0077B6),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: base,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF0A1628),
      cardTheme: CardThemeData(
        color: const Color(0xFF162033),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
