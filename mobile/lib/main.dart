import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/db_service.dart';
import 'services/transfer_service.dart';
import 'screens/home_screen.dart';
import 'screens/files_screen.dart';
import 'screens/settings_screen.dart';

class AppTheme {
  // Backgrounds (ContextL pure pitch black monochrome)
  static const bg         = Color(0xFF000000);
  static const surface    = Color(0xFF09090B);
  static const surface2   = Color(0xFF121214);

  // Flat monochrome borders and highlights
  static const gradPrimary = [Color(0xFFFFFFFF), Color(0xFFE4E4E7)];
  static const gradGreen   = [Color(0xFF22C55E), Color(0xFF16A34A)];
  static const gradRed     = [Color(0xFFEF4444), Color(0xFFDC2626)];
  static const gradOrange  = [Color(0xFFF97316), Color(0xFFEA580C)];
  static const gradBlue    = [Color(0xFF3B82F6), Color(0xFF2563EB)];

  static const borderGrad = [Color(0xFF27272A), Color(0xFF27272A)];

  // Text
  static const textPrimary   = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFA1A1AA);
  static const textMuted     = Color(0xFF52525B);

  // Accent
  static const accent       = Color(0xFFFFFFFF);
  static const accentGlow   = Color(0x1AFFFFFF);
}

class GradientCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final List<Color> borderColors;
  final Color? backgroundColor;

  const GradientCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 0,
    this.borderColors = AppTheme.borderGrad,
    this.backgroundColor = AppTheme.surface,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColors.first, width: 1),
        color: backgroundColor,
      ),
      padding: padding ?? EdgeInsets.zero,
      child: child,
    );
  }
}

class IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  const IconBox({
    super.key,
    required this.icon,
    this.color = AppTheme.textPrimary,
    this.size = 40,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF121214),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DbService().init();
  runApp(const DocTransitApp());
}

class DocTransitApp extends StatelessWidget {
  const DocTransitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TransferService()),
      ],
      child: MaterialApp(
        title: 'DocTransit',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFFFFFF),
            surface: Color(0xFF09090B),
            onSurface: Color(0xFFFFFFFF),
          ),
          scaffoldBackgroundColor: const Color(0xFF000000),
          useMaterial3: true,
          fontFamily: 'monospace',
        ),
        home: const MainShell(),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    FilesScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 64 + bottomInset),
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(bottom: bottomInset),
              decoration: const BoxDecoration(
                color: Color(0xFF09090B),
                border: Border(top: BorderSide(color: Color(0xFF27272A), width: 1)),
              ),
              child: SizedBox(
                height: 64,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(0, Icons.terminal_rounded, 'TERMINAL'),
                    _buildNavItem(1, Icons.folder_open_rounded, 'FILES'),
                    _buildNavItem(2, Icons.settings_rounded, 'CONFIG'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF18181B) : Colors.transparent,
          border: isActive
              ? Border.all(color: const Color(0xFFFFFFFF), width: 1)
              : Border.all(color: Colors.transparent, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                fontSize: 11,
                letterSpacing: 1.2,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
