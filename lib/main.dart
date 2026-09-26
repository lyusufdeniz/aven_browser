import 'package:flutter/material.dart';

import 'core/theme/aven_theme.dart';
import 'features/browser/browser_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AvenApp());
}

class AvenApp extends StatelessWidget {
  const AvenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aven Browser',
      debugShowCheckedModeBanner: false,
      theme: AvenColors.theme(),
      home: const BrowserPage(),
    );
  }
}
