import 'package:flutter/material.dart';

class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 32,
              child: Icon(Icons.person),
            ),
            const SizedBox(height: 12),
            const Text(
              'Mark Vane',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Text('Flutter Developer'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: null,
              child: const Text('Open profile'),
            ),
          ],
        ),
      ),
    );
  }
}
