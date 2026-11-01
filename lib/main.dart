import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/l10n/aven_strings.dart';
import 'core/platform/aven_flavor.dart';
import 'core/theme/aven_theme.dart';
import 'data/settings_store.dart';
import 'features/browser/browser_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AvenFlavor.load();
  await AvenStrings.load();
  if (AvenFlavor.isMobile) {
    avenThemeChoice.value = await BrowserStore().loadThemeChoice();
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  runApp(const AvenApp());
}

class AvenApp extends StatelessWidget {
  const AvenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: avenThemeChoice,
      builder: (context, choice, _) {
        return MaterialApp(
          title: 'Aven Browser',
          debugShowCheckedModeBanner: false,
          theme: AvenColors.lightTheme(),
          darkTheme: AvenColors.theme(),
          themeMode: AvenFlavor.isMobile ? avenThemeMode(choice) : ThemeMode.dark,
          home: const BrowserPage(),
        );
      },
    );
  }
}
