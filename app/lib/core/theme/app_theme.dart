import 'package:flutter/material.dart';

const _seed = Color(0xFF2E7D32);

/// Material 3, light and dark (plan item 51).
ThemeData appTheme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
