import 'package:flutter/material.dart';

class WifiConfigPage extends StatelessWidget {
  const WifiConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi配网')),
      body: const Center(child: Text('WiFi配网页面')),
    );
  }
}
