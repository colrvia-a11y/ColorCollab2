import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:color_canvas/firestore/firestore_data_schema.dart';
import 'package:color_canvas/utils/color_utils.dart';
import 'package:color_canvas/screens/roller_screen.dart';
import 'package:color_canvas/screens/library_screen.dart';
import 'package:color_canvas/screens/search_screen.dart';
import 'package:color_canvas/screens/explore_screen.dart';
import 'package:color_canvas/screens/settings_screen.dart';
import 'package:color_canvas/widgets/more_menu_sheet.dart';

abstract class HomeScreenPaintSelection {
  void onPaintSelectedFromSearch(Paint paint);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> implements HomeScreenPaintSelection {
  int _currentIndex = 0;
  final GlobalKey<RollerScreenStatePublic> _rollerKey = GlobalKey<RollerScreenStatePublic>();
  
  late final List<Widget> _screens = [
    RollerScreen(key: _rollerKey),
    const ExploreScreen(),
  ];

  @override
  void onPaintSelectedFromSearch(Paint paint) {
    // Switch to roller screen
    setState(() {
      _currentIndex = 0;
    });
    
    // Show selection dialog to choose which column to replace
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showColumnSelectionDialog(paint);
    });
  }

  void _showMoreMenuSheet() {
    HapticFeedback.selectionClick();
    
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      builder: (_) => const MoreMenuSheet(),
    );
  }

  void _showColumnSelectionDialog(Paint paint) {
    final rollerState = _rollerKey.currentState;
    if (rollerState == null) return;

    final paletteSize = rollerState.getPaletteSize();
    
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Replace Color',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Select which color to replace with ${paint.name}',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            
            ...List.generate(paletteSize, (index) {
              final currentPaint = rollerState.getPaintAtIndex(index);
              return ListTile(
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: currentPaint != null ? ColorUtils.getPaintColor(currentPaint) : Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey[400]!),
                  ),
                ),
                title: Text(currentPaint?.name ?? 'Color ${index + 1}'),
                subtitle: currentPaint != null ? Text(currentPaint.brandName) : null,
                onTap: () {
                  rollerState.replacePaintAtIndex(index, paint);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Replaced color ${index + 1} with ${paint.name}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              );
            }),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 2) {
            // "More" tapped - show sheet instead of navigating
            _showMoreMenuSheet();
          } else {
            // Normal navigation
            setState(() => _currentIndex = index);
          }
        },
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.color_lens_outlined),
            activeIcon: Icon(Icons.color_lens),
            label: 'Design',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore),
            label: 'Explore',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu),
            label: 'More',
          ),
        ],
      ),
    );
  }
}