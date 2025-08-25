import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:color_canvas/firestore/firestore_data_schema.dart';
import 'package:color_canvas/utils/color_utils.dart';
import 'package:color_canvas/screens/home_screen.dart';
import 'package:color_canvas/screens/roller_screen.dart';
import 'package:color_canvas/screens/library_screen.dart';
import 'package:color_canvas/screens/search_screen.dart';
import 'package:color_canvas/screens/explore_screen.dart';
import 'package:color_canvas/screens/settings_screen.dart';
import 'package:color_canvas/services/firebase_service.dart';
import 'package:color_canvas/services/analytics_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

class ColorStoryDetailScreen extends StatefulWidget {
  final ColorStory colorStory;

  const ColorStoryDetailScreen({
    super.key,
    required this.colorStory,
  });

  @override
  State<ColorStoryDetailScreen> createState() => _ColorStoryDetailScreenState();
}

class _ColorStoryDetailScreenState extends State<ColorStoryDetailScreen>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _cardKeys = {};
  Color _backgroundColor = const Color(0xFFF8F9FA);
  late AnimationController _backgroundController;
  late Animation<Color?> _backgroundAnimation;

  @override
  void initState() {
    super.initState();
    
    // Track color story open
    _trackColorStoryOpen();
    _backgroundController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _backgroundAnimation = ColorTween(
      begin: const Color(0xFFF8F9FA),
      end: const Color(0xFFF8F9FA),
    ).animate(CurvedAnimation(
      parent: _backgroundController,
      curve: Curves.easeInOut,
    ));

    // Initialize card keys
    for (int i = 0; i < widget.colorStory.palette.length; i++) {
      _cardKeys[i] = GlobalKey();
    }

    _scrollController.addListener(_onScroll);
  }
  
  void _trackColorStoryOpen() {
    AnalyticsService.instance.trackColorStoryOpen(
      storyId: widget.colorStory.id ?? 'unknown',
      slug: widget.colorStory.slug,
      title: widget.colorStory.title,
      themes: widget.colorStory.themes,
      families: widget.colorStory.families,
      rooms: widget.colorStory.rooms,
      isFeatured: widget.colorStory.isFeatured,
      source: 'detail_view',
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _backgroundController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final screenHeight = MediaQuery.of(context).size.height;
    final centerY = screenHeight * 0.5;

    for (int i = 0; i < widget.colorStory.palette.length; i++) {
      final key = _cardKeys[i];
      if (key != null && key.currentContext != null) {
        final box = key.currentContext!.findRenderObject() as RenderBox?;
        if (box != null) {
          final position = box.localToGlobal(Offset.zero);
          final cardCenter = position.dy + (box.size.height * 0.5);
          
          // Check if this card is near the center of screen
          if ((cardCenter - centerY).abs() < screenHeight * 0.3) {
            final paletteItem = widget.colorStory.palette[i];
            final newColor = ColorUtils.hexToColor(paletteItem.hex);
            final tintedColor = ColorUtils.createAccessibleTintedBackground(
              const Color(0xFFF8F9FA), 
              newColor, 
              maxOpacity: 0.06,
            );
            
            if (tintedColor != _backgroundColor) {
              setState(() {
                _backgroundColor = tintedColor;
              });
              
              _backgroundAnimation = ColorTween(
                begin: _backgroundAnimation.value,
                end: tintedColor,
              ).animate(CurvedAnimation(
                parent: _backgroundController,
                curve: Curves.easeInOut,
              ));
              
              _backgroundController.forward(from: 0);
            }
            break;
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _backgroundAnimation,
      builder: (context, child) {
        final bgColor = _backgroundAnimation.value ?? _backgroundColor;
        final textColor = ColorUtils.preferredTextColor(bgColor);
        
        return Scaffold(
          backgroundColor: bgColor,
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Parallax Hero Header
              SliverAppBar(
                expandedHeight: 300.0,
                floating: false,
                pinned: true,
                backgroundColor: bgColor,
                foregroundColor: textColor,
                flexibleSpace: FlexibleSpaceBar(
                  title: Semantics(
                    header: true,
                    child: Text(
                      widget.colorStory.title,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            offset: const Offset(0, 1),
                            blurRadius: 2,
                            color: textColor == Colors.white 
                                ? Colors.black.withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  background: widget.colorStory.heroImageUrl?.isNotEmpty == true
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              child: CachedNetworkImage(
                                imageUrl: widget.colorStory.heroImageUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey[200],
                                  child: const Center(
                                    child: Icon(
                                      Icons.image_outlined,
                                      size: 48,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        ColorUtils.hexToColor(widget.colorStory.palette.first.hex),
                                        ColorUtils.hexToColor(widget.colorStory.palette.last.hex),
                                      ],
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.broken_image_outlined,
                                        size: 48,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Image unavailable',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.3),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                ColorUtils.hexToColor(widget.colorStory.palette.first.hex),
                                ColorUtils.hexToColor(widget.colorStory.palette.last.hex),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
              
              // Content
              SliverList(
                delegate: SliverChildListDelegate([
                  // Intro Paragraph
                  if (widget.colorStory.description.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(24.0),
                      child: Semantics(
                        label: 'Color story description: ${widget.colorStory.description}',
                        child: Text(
                          widget.colorStory.description,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: textColor,
                            height: 1.6,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  
                  // Color Reveal Cards
                  ...widget.colorStory.palette.asMap().entries.map((entry) {
                    final index = entry.key;
                    final paletteItem = entry.value;
                    return ColorRevealCard(
                      key: _cardKeys[index],
                      paletteItem: paletteItem,
                      textColor: textColor,
                    );
                  }),
                  
                  // CTA Section
                  Container(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        
                        // Use This Color Story Button
                        Semantics(
                          label: 'Import ${widget.colorStory.title} palette to Paint Roller',
                          hint: 'Tap to load this color story into the roller for customization',
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _useColorStory,
                              icon: const Icon(Icons.palette),
                              label: const Text('Use This Color Story'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Secondary Actions Row
                        Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                label: 'Save ${widget.colorStory.title} to library',
                                hint: 'Tap to add this color story to your saved collections',
                                child: OutlinedButton.icon(
                                  onPressed: _saveToLibrary,
                                  icon: const Icon(Icons.bookmark_outline),
                                  label: const Text('Save'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    foregroundColor: textColor,
                                    side: BorderSide(color: textColor.withValues(alpha: 0.3)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            
                            const SizedBox(width: 16),
                            
                            Expanded(
                              child: Semantics(
                                label: 'Share ${widget.colorStory.title}',
                                hint: 'Tap to share this color story with others',
                                child: OutlinedButton.icon(
                                  onPressed: _shareColorStory,
                                  icon: const Icon(Icons.share),
                                  label: const Text('Share'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    foregroundColor: textColor,
                                    side: BorderSide(color: textColor.withValues(alpha: 0.3)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  void _useColorStory() {
    // Track analytics event
    AnalyticsService.instance.trackColorStoryUseClick(
      storyId: widget.colorStory.id ?? 'unknown',
      slug: widget.colorStory.slug,
      title: widget.colorStory.title,
      paletteColorCount: widget.colorStory.palette.length,
      colorHexCodes: widget.colorStory.palette.map((p) => p.hex).toList(),
    );
    
    try {
      // Convert Color Story palette to Paint objects
      final paints = ColorUtils.colorStoryPaletteToPaints(widget.colorStory.palette);
      
      if (paints.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No colors available to import'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // Navigate back to home screen with initial colors
      Navigator.of(context).popUntil((route) => route.isFirst);
      
      // Navigate to Roller with initial paints
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => _RollerWithColorStoryWrapper(
            colorStory: widget.colorStory,
            initialPaints: paints,
          ),
        ),
      );
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error importing color story: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _saveToLibrary() async {
    // Track analytics event
    AnalyticsService.instance.trackColorStorySaveClick(
      storyId: widget.colorStory.id ?? 'unknown',
      slug: widget.colorStory.slug,
      title: widget.colorStory.title,
      isAlreadySaved: false, // TODO: Check if already saved
    );
    
    try {
      // Save each color from the story as a favorite
      for (final paletteItem in widget.colorStory.palette) {
        if (paletteItem.paintId?.isNotEmpty == true) {
          await FirebaseService.addFavoritePaint(paletteItem.paintId!);
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Color story saved to your library'),
              ],
            ),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'VIEW LIBRARY',
              textColor: Colors.white,
              onPressed: () {
                Navigator.of(context).pushNamed('/library');
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Failed to save to library. Please try again.')),
              ],
            ),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: _saveToLibrary,
            ),
          ),
        );
      }
    }
  }

  void _shareColorStory() async {
    // Track analytics event
    AnalyticsService.instance.trackColorStoryShareClick(
      storyId: widget.colorStory.id ?? 'unknown',
      slug: widget.colorStory.slug,
      title: widget.colorStory.title,
      shareMethod: 'native_share',
    );
    
    try {
      // Ensure we have a slug (fallback to id if null)
      final slug = widget.colorStory.slug.isNotEmpty 
          ? widget.colorStory.slug 
          : widget.colorStory.id ?? 'unknown';
      
      // Create compact swatch summary (2-3 key swatches)
      final keySwatches = widget.colorStory.palette.take(3).map((p) {
        final role = p.role.split('_').map((word) => 
          word[0].toUpperCase() + word.substring(1)).join(' ');
        return '$role ${p.hex}';
      }).join(' • ');
      
      // Create deep link
      // TODO: Update with actual web domain when deployed
      final deepLink = 'myapp://story/$slug';
      
      final shareText = '''Color Story: ${widget.colorStory.title}
$keySwatches
$deepLink''';
      
      await Share.share(shareText);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Color story shared successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Fallback to clipboard if sharing fails
      final slug = widget.colorStory.slug.isNotEmpty 
          ? widget.colorStory.slug 
          : widget.colorStory.id ?? 'unknown';
      final keySwatches = widget.colorStory.palette.take(3).map((p) {
        final role = p.role.split('_').map((word) => 
          word[0].toUpperCase() + word.substring(1)).join(' ');
        return '$role ${p.hex}';
      }).join(' • ');
      final fallbackText = '''Color Story: ${widget.colorStory.title}
$keySwatches
myapp://story/$slug''';
      await Clipboard.setData(ClipboardData(text: fallbackText));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.content_copy, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Color story details copied to clipboard'),
              ],
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }
  }
  
  void _showErrorDialog(String title, String message, VoidCallback? retryAction) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error, color: Colors.red, size: 24),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          if (retryAction != null)
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                retryAction();
              },
              child: const Text('RETRY'),
            ),
        ],
      ),
    );
  }
  
  void _showOfflineMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share feature coming soon!'),
      ),
    );
  }
}

class ColorRevealCard extends StatelessWidget {
  final ColorStoryPalette paletteItem;
  final Color textColor;

  const ColorRevealCard({
    super.key,
    required this.paletteItem,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final swatchColor = ColorUtils.hexToColor(paletteItem.hex);
    final cardTextColor = ColorUtils.preferredTextColor(swatchColor);
    
    return Semantics(
      label: '${paletteItem.role}, ${paletteItem.name ?? paletteItem.hex}, ${(paletteItem.brandName ?? '')} ${(paletteItem.code ?? '')}',
      hint: 'Color card with details and usage tips',
      button: false,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: textColor.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Color Swatch Block
            Container(
              height: 120,
              color: swatchColor,
              child: Stack(
                children: [
                  // Gradient overlay for better text readability
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          cardTextColor == Colors.white 
                              ? Colors.black.withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.3),
                        ],
                      ),
                    ),
                  ),
                  
                  // Color Info Overlay
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          excludeSemantics: true,
                          child: Text(
                            paletteItem.role.toUpperCase(),
                            style: TextStyle(
                              color: cardTextColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Semantics(
                          excludeSemantics: true,
                          child: Text(
                            paletteItem.name ?? 'Custom Color',
                            style: TextStyle(
                              color: cardTextColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (paletteItem.brandName?.isNotEmpty == true && paletteItem.code?.isNotEmpty == true)
                          Semantics(
                            excludeSemantics: true,
                            child: Text(
                              '${paletteItem.brandName} • ${paletteItem.code}',
                              style: TextStyle(
                                color: cardTextColor.withValues(alpha: 0.9),
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Content Section
            Container(
              color: Theme.of(context).cardColor,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Psychology Snippet
                  if (paletteItem.psychology?.isNotEmpty == true) ...[
                    Semantics(
                      label: 'Color psychology: ${paletteItem.psychology}',
                      child: Text(
                        paletteItem.psychology!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // Usage Tips
                  if (paletteItem.usageTips?.isNotEmpty == true)
                    Semantics(
                      label: 'Usage tips: ${paletteItem.usageTips}',
                      child: RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            height: 1.4,
                          ),
                          children: [
                            TextSpan(
                              text: 'How to use: ',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                            TextSpan(text: paletteItem.usageTips!),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

/// Wrapper to navigate to Home screen with Roller tab showing Color Story palette
class _RollerWithColorStoryWrapper extends StatefulWidget {
  final ColorStory colorStory;
  final List<Paint> initialPaints;

  const _RollerWithColorStoryWrapper({
    required this.colorStory,
    required this.initialPaints,
  });

  @override
  State<_RollerWithColorStoryWrapper> createState() => _RollerWithColorStoryWrapperState();
}

class _RollerWithColorStoryWrapperState extends State<_RollerWithColorStoryWrapper> {
  @override
  void initState() {
    super.initState();
    
    // Show success message after navigation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Color Story "${widget.colorStory.title}" imported to Roller',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'EXPLORE MORE',
              textColor: Colors.white,
              onPressed: () {
                // Switch to Explore tab
                if (context.findAncestorStateOfType<_HomeScreenWithRollerInitialColorsState>() != null) {
                  context.findAncestorStateOfType<_HomeScreenWithRollerInitialColorsState>()!._switchToExplore();
                }
              },
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _HomeScreenWithRollerInitialColors(
      initialPaints: widget.initialPaints,
      colorStoryTitle: widget.colorStory.title,
    );
  }
}

/// Home screen variant that starts with Roller tab and initial paints
class _HomeScreenWithRollerInitialColors extends StatefulWidget {
  final List<Paint> initialPaints;
  final String colorStoryTitle;

  const _HomeScreenWithRollerInitialColors({
    required this.initialPaints,
    required this.colorStoryTitle,
  });

  @override
  State<_HomeScreenWithRollerInitialColors> createState() => _HomeScreenWithRollerInitialColorsState();
}

class _HomeScreenWithRollerInitialColorsState extends State<_HomeScreenWithRollerInitialColors> {
  int _currentIndex = 0; // Start with Roller tab active
  
  void _switchToExplore() {
    setState(() {
      _currentIndex = 3; // Explore tab index
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Roller with initial paints
          RollerScreen(
            initialPaints: widget.initialPaints,
          ),
          // Tab 1: Library
          const LibraryScreen(),
          // Tab 2: Search
          const SearchScreen(),
          // Tab 3: Explore
          const ExploreScreen(),
          // Tab 4: Settings
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.casino),
            label: 'Roll',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore),
            label: 'Explore',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}