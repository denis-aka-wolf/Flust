import 'package:flutter/material.dart';
import 'widgets/profile_card.w.dart';

void main() => runApp(const FlustExampleApp());

class FlustExampleApp extends StatelessWidget {
  const FlustExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flust Example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const Scaffold(
        body: Center(child: ProfileCard()),
      ),
    );
  }
}
