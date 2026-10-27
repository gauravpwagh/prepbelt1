import 'package:flutter/material.dart';

// Placeholder shell until M3 adds bootstrap, routing and the screens
// (plan items 46–49).
void main() => runApp(const PrepBeltApp());

class PrepBeltApp extends StatelessWidget {
  const PrepBeltApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PrepBelt',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF2E7D32)),
        home: const Scaffold(body: Center(child: Text('PrepBelt'))),
      );
}
