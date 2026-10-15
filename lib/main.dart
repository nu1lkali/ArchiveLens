import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/services/settings_service.dart';
import 'src/state/library_controller.dart';
import 'src/ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 设置（7z 路径、缩略图参数等）需要先读磁盘，所以提前异步加载
  final settings = await SettingsService.load();

  runApp(ArchiveLensApp(settings: settings));
}

class ArchiveLensApp extends StatelessWidget {
  final SettingsService settings;

  const ArchiveLensApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<LibraryController>(
          create: (_) => LibraryController(settings),
        ),
      ],
      child: MaterialApp(
        title: 'ArchiveLens · 图片压缩包管理器',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF5B6CFF),
          brightness: Brightness.light,
          visualDensity: VisualDensity.compact,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF5B6CFF),
          brightness: Brightness.dark,
          visualDensity: VisualDensity.compact,
        ),
        themeMode: ThemeMode.system,
        home: const HomePage(),
      ),
    );
  }
}
