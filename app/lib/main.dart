import 'package:flutter/foundation.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:tapdancer/providers/ble_provider.dart';
import 'package:tapdancer/screens/config_screen.dart';
import 'package:tapdancer/screens/devices_screen.dart';
import 'package:tapdancer/screens/settings_screen.dart';
import 'package:tapdancer/utils/utils.dart';
import 'package:tapdancer/widgets/bottom_navigation_bar.dart';
import 'package:window_manager/window_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tapdancer/utils/app_theme.dart';
import 'package:tapdancer/utils/logger.dart';
import 'package:tapdancer/utils/preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (defaultTargetPlatform != TargetPlatform.android) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Initialize logger.
  final Logger logger = Log.instance;

  // Initialize shared preferences key value storage.
  await PreferencesManager.init();

  // Initialize package information.
  await PackageInformation.init();

  // Set windows specific settings.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    final window = WindowManager.instance.getCurrent();
    if (window != null) {
      final windowSize = const Size(AppColor.windowWidth, AppColor.windowHeightRegularWindows).toNative();
      window.title = "TapDancer";
      window.setSize(windowSize, false);
      window.minimumSize = windowSize;
      window.center();
      window.show();
      window.focus();
    }
  }

  // Check required permissions.
  if (!kIsWeb && (await Permission.bluetoothScan.request().isDenied || await Permission.bluetoothConnect.request().isDenied)) {
    logger.e("BLE permissions denied!");
  }

  runApp(
    ProviderScope(
      child: TapDancerController(),
    ),
  );
}

class TapDancerController extends StatelessWidget {
  const TapDancerController({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TapDancer',
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.dark,
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Theme(
          data: AppTheme.getAppTheme(context),
          child: child!,
        );
      },
      home: MainShell(),
    );
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    DevicesScreen(),
    ConfigScreen(),
    SettingsScreen(),
  ];

  void _onNavSelected(int index) {
    setState(() {
      if (index >= _pages.length) index = _pages.length - 1;
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Start ble provider.
    final _ = ref.read(bleProvider.notifier);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBarWidget(
        onItemSelected: _onNavSelected,
      ),
    );
  }
}
