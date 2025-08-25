import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:color_canvas/services/firebase_service.dart';
import 'package:color_canvas/services/analytics_service.dart';
import 'package:color_canvas/firestore/firestore_data_schema.dart';
import 'package:color_canvas/screens/color_story_detail_screen.dart';
import 'package:color_canvas/screens/story_studio_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // Performance optimization - debounce search
  Timer? _searchDebounce;
  final Duration _searchDelay = const Duration(milliseconds: 500);
  
  List<ColorStory> _stories = [];
  List<ColorStory> _filteredStories = [];
  bool _isLoading = false;
  bool _hasMoreData = true;
  bool _hasError = false;
  String _errorMessage = '';
  final int _pageSize = 24;
  DocumentSnapshot? _lastDocument; // Cursor for pagination
  
  // Filter states
  final Set<String> _selectedThemes = <String>{};
  final Set<String> _selectedFamilies = <String>{};
  final Set<String> _selectedRooms = <String>{};
  String _searchQuery = '';
  
  // Filter options (loaded dynamically from Firestore)
  List<String> _themeOptions = [];
  List<String> _familyOptions = [];
  List<String> _roomOptions = [];
  bool _taxonomiesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTaxonomies();
    _loadColorStories();
    _scrollController.addListener(_onScroll);
    
    // Track screen view
    AnalyticsService.instance.screenView('explore_color_stories');
  }

  Future<void> _loadTaxonomies() async {
    try {
      final taxonomies = await FirebaseService.getTaxonomyOptions();
      setState(() {
        _themeOptions = taxonomies['themes'] ?? [];
        _familyOptions = taxonomies['families'] ?? [];
        _roomOptions = taxonomies['rooms'] ?? [];
        _taxonomiesLoading = false;
      });
    } catch (e) {
      // Use defaults on error
      setState(() {
        _themeOptions = ['coastal', 'modern-farmhouse', 'traditional', 'contemporary', 'rustic', 'minimalist'];
        _familyOptions = ['greens', 'blues', 'neutrals', 'warm-neutrals', 'cool-neutrals', 'whites', 'grays'];
        _roomOptions = ['kitchen', 'living', 'bedroom', 'bathroom', 'dining', 'exterior', 'office'];
        _taxonomiesLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreStories();
    }
  }

  Future<void> _loadColorStories() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final result = await FirebaseService.getColorStoriesWithCursor(
        themes: _selectedThemes.isEmpty ? null : _selectedThemes.toList(),
        families: _selectedFamilies.isEmpty ? null : _selectedFamilies.toList(),
        rooms: _selectedRooms.isEmpty ? null : _selectedRooms.toList(),
        limit: _pageSize,
        startAfter: null, // First page, no cursor
      );
      
      final stories = result['stories'] as List<ColorStory>;
      
      setState(() {
        _stories = stories;
        _lastDocument = result['lastDocument'] as DocumentSnapshot?;
        _hasMoreData = result['hasMore'] as bool;
        _applyTextFilter();
      });
    } catch (e) {
      debugPrint('Error loading color stories: $e');
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load color stories. Please check your connection.';
        // Fallback to sample data for development
        _stories = _getSampleStories();
        _applyTextFilter();
      });
      
      // Don't show global SnackBar - handle error locally in UI
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreStories() async {
    if (_isLoading || !_hasMoreData) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final result = await FirebaseService.getColorStoriesWithCursor(
        themes: _selectedThemes.isEmpty ? null : _selectedThemes.toList(),
        families: _selectedFamilies.isEmpty ? null : _selectedFamilies.toList(),
        rooms: _selectedRooms.isEmpty ? null : _selectedRooms.toList(),
        limit: _pageSize,
        startAfter: _lastDocument, // Use cursor for next page
      );
      
      final newStories = result['stories'] as List<ColorStory>;
      
      setState(() {
        _stories.addAll(newStories);
        _lastDocument = result['lastDocument'] as DocumentSnapshot?;
        _hasMoreData = result['hasMore'] as bool;
        _applyTextFilter();
      });
    } catch (e) {
      debugPrint('Error loading more stories: $e');
      // Don't show global SnackBar for load more failures - handle silently
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _applyTextFilter() {
    if (_searchQuery.isEmpty) {
      _filteredStories = List.from(_stories);
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredStories = _stories.where((story) {
        final titleMatch = story.title.toLowerCase().contains(query);
        final tagsMatch = story.tags.any((tag) => tag.toLowerCase().contains(query));
        return titleMatch || tagsMatch;
      }).toList();
    }
  }

  void _onSearchChanged(String query) {
    // Cancel previous debounce timer
    _searchDebounce?.cancel();
    
    setState(() {
      _searchQuery = query;
      _applyTextFilter();
    });
    
    // Debounced analytics tracking to avoid too many events
    if (query.trim().isNotEmpty) {
      _searchDebounce = Timer(_searchDelay, () {
        final startTime = DateTime.now();
        _applyTextFilter();
        final searchDuration = DateTime.now().difference(startTime).inMilliseconds.toDouble();
        
        final activeFilters = <String>[
          ..._selectedThemes.map((t) => 'theme:$t'),
          ..._selectedFamilies.map((f) => 'family:$f'),
          ..._selectedRooms.map((r) => 'room:$r'),
        ];
        
        AnalyticsService.instance.trackExploreSearch(
          searchQuery: query.trim(),
          resultCount: _filteredStories.length,
          searchDurationMs: searchDuration,
          activeFilters: activeFilters.isNotEmpty ? activeFilters : null,
        );
      });
    }
  }

  void _onFilterChanged() {
    _hasMoreData = true;
    _lastDocument = null; // Reset cursor for new filter query
    _loadColorStories();
    
    // Track filter analytics
    AnalyticsService.instance.trackExploreFilterChange(
      selectedThemes: _selectedThemes.toList(),
      selectedFamilies: _selectedFamilies.toList(),
      selectedRooms: _selectedRooms.toList(),
    );
  }

  void _toggleTheme(String theme) {
    final wasSelected = _selectedThemes.contains(theme);
    setState(() {
      if (wasSelected) {
        _selectedThemes.remove(theme);
      } else {
        _selectedThemes.add(theme);
      }
    });
    
    // Enhanced analytics tracking
    AnalyticsService.instance.trackExploreFilterChange(
      selectedThemes: _selectedThemes.toList(),
      selectedFamilies: _selectedFamilies.toList(),
      selectedRooms: _selectedRooms.toList(),
      changeType: wasSelected ? 'theme_removed' : 'theme_added',
      totalResultCount: _filteredStories.length,
    );
    
    _onFilterChanged();
  }

  void _toggleFamily(String family) {
    final wasSelected = _selectedFamilies.contains(family);
    setState(() {
      if (wasSelected) {
        _selectedFamilies.remove(family);
      } else {
        _selectedFamilies.add(family);
      }
    });
    
    // Enhanced analytics tracking
    AnalyticsService.instance.trackExploreFilterChange(
      selectedThemes: _selectedThemes.toList(),
      selectedFamilies: _selectedFamilies.toList(),
      selectedRooms: _selectedRooms.toList(),
      changeType: wasSelected ? 'family_removed' : 'family_added',
      totalResultCount: _filteredStories.length,
    );
    
    _onFilterChanged();
  }

  void _toggleRoom(String room) {
    final wasSelected = _selectedRooms.contains(room);
    setState(() {
      if (wasSelected) {
        _selectedRooms.remove(room);
      } else {
        _selectedRooms.add(room);
      }
    });
    
    // Enhanced analytics tracking
    AnalyticsService.instance.trackExploreFilterChange(
      selectedThemes: _selectedThemes.toList(),
      selectedFamilies: _selectedFamilies.toList(),
      selectedRooms: _selectedRooms.toList(),
      changeType: wasSelected ? 'room_removed' : 'room_added',
      totalResultCount: _filteredStories.length,
    );
    
    _onFilterChanged();
  }

  List<ColorStory> _getSampleStories() {
    // Sample data for development/offline mode
    return [
      ColorStory(
        id: 'sample-1',
        title: 'Coastal Serenity',
        slug: 'coastal-serenity',
        heroImageUrl: 'https://pixabay.com/get/g1d5c9aa83a66d093c7e4b4fc7b97b2b2a83ae7a311c8f2f0d621269c20bd3109f26e62dbe18eb3717b515c4738252cdef0a5fb70596b60152ed0ed0b61c5ddef_1280.jpg',
        themes: ['coastal', 'contemporary'],
        families: ['blues', 'neutrals'],
        rooms: ['living', 'bedroom'],
        tags: ['ocean', 'calming', 'fresh'],
        description: 'Inspired by ocean waves and sandy shores',
        isFeatured: true,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
        facets: ['theme:coastal', 'theme:contemporary', 'family:blues', 'family:neutrals', 'room:living', 'room:bedroom'],
        palette: [
          ColorStoryPalette(
            role: 'main',
            hex: '#4A90A4',
            name: 'Ocean Blue',
            brandName: 'Sherwin-Williams',
            code: 'SW 6501',
            psychology: 'Promotes tranquility and calm, evoking the serenity of ocean depths.',
            usageTips: 'Perfect for bedrooms and bathrooms where relaxation is key.',
          ),
          ColorStoryPalette(
            role: 'accent',
            hex: '#E8F4F8',
            name: 'Sea Foam',
            brandName: 'Benjamin Moore',
            code: 'OC-58',
            psychology: 'Light and airy, creates a sense of freshness and renewal.',
            usageTips: 'Ideal for trim work and ceiling accents to brighten spaces.',
          ),
          ColorStoryPalette(
            role: 'trim',
            hex: '#F5F5DC',
            name: 'Sandy Beige',
            brandName: 'Behr',
            code: 'N240-1',
            psychology: 'Warm and grounding, provides stability and comfort.',
            usageTips: 'Use as a neutral base to balance cooler tones.',
          ),
        ],
      ),
      ColorStory(
        id: 'sample-2',
        title: 'Modern Farmhouse',
        slug: 'modern-farmhouse',
        heroImageUrl: 'https://pixabay.com/get/ga04013479135d1420a173525047d5aa53d70a7cef34a22c34c59d3edfee6daff2a8feee41d7e42aac0dd6462898e291ef492fa25b9984dd761c6f49b9cf20a68_1280.jpg',
        themes: ['modern-farmhouse', 'rustic'],
        families: ['warm-neutrals', 'whites'],
        rooms: ['kitchen', 'dining'],
        tags: ['cozy', 'natural', 'warm'],
        description: 'Warm and inviting farmhouse aesthetic',
        isFeatured: false,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        updatedAt: DateTime.now().subtract(const Duration(days: 2)),
        facets: ['theme:modern-farmhouse', 'theme:rustic', 'family:warm-neutrals', 'family:whites', 'room:kitchen', 'room:dining'],
        palette: [
          ColorStoryPalette(
            role: 'main',
            hex: '#F7F3E9',
            name: 'Creamy White',
            brandName: 'Benjamin Moore',
            code: 'OC-14',
            psychology: 'Warm and inviting, creates a cozy and welcoming atmosphere.',
            usageTips: 'Excellent for main walls in kitchens and dining areas.',
          ),
          ColorStoryPalette(
            role: 'accent',
            hex: '#8B7355',
            name: 'Weathered Wood',
            brandName: 'Sherwin-Williams',
            code: 'SW 2841',
            psychology: 'Natural and rustic, brings warmth and earthiness to spaces.',
            usageTips: 'Perfect for accent walls and built-in cabinetry.',
          ),
          ColorStoryPalette(
            role: 'trim',
            hex: '#2F2F2F',
            name: 'Charcoal',
            brandName: 'Behr',
            code: 'S350-7',
            psychology: 'Bold and sophisticated, adds depth and contrast.',
            usageTips: 'Use sparingly on trim and window frames for definition.',
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Color Stories'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const StoryStudioScreen(),
            ),
          );
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        tooltip: 'Create Color Story',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              onSubmitted: (query) {
                if (query.trim().isNotEmpty) {
                  final startTime = DateTime.now();
                  _applyTextFilter();
                  final searchDuration = DateTime.now().difference(startTime).inMilliseconds.toDouble();
                  
                  AnalyticsService.instance.trackExploreSearch(
                    searchQuery: query.trim(),
                    resultCount: _filteredStories.length,
                    searchDurationMs: searchDuration,
                  );
                }
              },
              decoration: InputDecoration(
                hintText: 'Search stories or tags…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          
          // Filter Chips
          SizedBox(
            height: 120,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFilterSection('Style', _themeOptions, _selectedThemes, _toggleTheme),
                  const SizedBox(height: 8),
                  _buildFilterSection('Family', _familyOptions, _selectedFamilies, _toggleFamily),
                  const SizedBox(height: 8),
                  _buildFilterSection('Room', _roomOptions, _selectedRooms, _toggleRoom),
                ],
              ),
            ),
          ),
          
          const Divider(height: 1),
          
          // Results Grid
          Expanded(
            child: _buildResultsGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection(String title, List<String> options, Set<String> selected, Function(String) onToggle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: options.map((option) => FilterChip(
            label: Text(
              option.replaceAll('-', ' '),
              style: const TextStyle(fontSize: 12),
            ),
            selected: selected.contains(option),
            onSelected: (_) => onToggle(option),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildResultsGrid() {
    if (_isLoading && _filteredStories.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading color stories...'),
          ],
        ),
      );
    }
    
    if (_hasError && _filteredStories.isEmpty) {
      return _buildErrorState();
    }

    if (_filteredStories.isEmpty) {
      return _buildEmptyState();
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _getGridCrossAxisCount(context),
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _filteredStories.length + (_hasMoreData ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _filteredStories.length) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        
        return ColorStoryCard(story: _filteredStories[index]);
      },
    );
  }

  Widget _buildEmptyState() {
    // Generate dynamic suggestions based on current filter state
    final suggestion = _buildDynamicSuggestion();
    
    // Track empty state analytics
    AnalyticsService.instance.trackExploreEmptyStateShown(
      selectedThemes: _selectedThemes.toList(),
      selectedFamilies: _selectedFamilies.toList(),
      selectedRooms: _selectedRooms.toList(),
      searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
      suggestedAction: suggestion['action'] ?? 'unknown',
    );
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.palette_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No matches yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              suggestion['message'] ?? 'Try adjusting your filters or search terms',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            
            // Clear filters button (always shown when filters are active)
            if (_selectedThemes.isNotEmpty || _selectedFamilies.isNotEmpty || _selectedRooms.isNotEmpty || _searchQuery.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Track clear filters action
                    AnalyticsService.instance.trackColorStoriesEngagement(
                      action: 'clear_filters_from_empty_state',
                      additionalData: {
                        'had_themes': _selectedThemes.isNotEmpty,
                        'had_families': _selectedFamilies.isNotEmpty,
                        'had_rooms': _selectedRooms.isNotEmpty,
                        'had_search': _searchQuery.isNotEmpty,
                      },
                    );
                    
                    setState(() {
                      _selectedThemes.clear();
                      _selectedFamilies.clear();
                      _selectedRooms.clear();
                      _searchQuery = '';
                      _searchController.clear();
                    });
                    _onFilterChanged();
                  },
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear filters'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  /// Build dynamic suggestion message based on current filter state
  Map<String, String> _buildDynamicSuggestion() {
    final hasThemes = _selectedThemes.isNotEmpty;
    final hasFamilies = _selectedFamilies.isNotEmpty;
    final hasRooms = _selectedRooms.isNotEmpty;
    final hasSearch = _searchQuery.isNotEmpty;
    
    // If all three filter categories are selected, suggest removing the most restrictive one
    if (hasThemes && hasFamilies && hasRooms) {
      return {
        'message': 'This combination might be too specific. Try removing one of your filters to find more stories.',
        'action': 'remove_filter_combination',
      };
    }
    
    // If search query + multiple filters
    if (hasSearch && (hasThemes || hasFamilies || hasRooms)) {
      return {
        'message': 'Your search combined with filters might be too narrow. Try clearing your search or removing some filters.',
        'action': 'simplify_search_and_filters',
      };
    }
    
    // If only search query
    if (hasSearch && !hasThemes && !hasFamilies && !hasRooms) {
      return {
        'message': 'No stories match your search. Try different keywords or browse by style instead.',
        'action': 'modify_search_query',
      };
    }
    
    // If only rooms are selected (most restrictive)
    if (hasRooms && !hasThemes && !hasFamilies) {
      return {
        'message': 'Try adding a color family like "neutrals" or "blues" to find stories for this room.',
        'action': 'add_family_filter',
      };
    }
    
    // If themes + families but no rooms
    if (hasThemes && hasFamilies && !hasRooms) {
      return {
        'message': 'This style and color combination might be rare. Try expanding to more color families.',
        'action': 'expand_families',
      };
    }
    
    // If only themes selected
    if (hasThemes && !hasFamilies && !hasRooms) {
      return {
        'message': 'Try adding a color family like "neutrals" or "warm-neutrals" to discover stories in this style.',
        'action': 'add_family_to_theme',
      };
    }
    
    // If only families selected
    if (hasFamilies && !hasThemes && !hasRooms) {
      return {
        'message': 'Try adding a style like "modern-farmhouse" or "contemporary" to find stories with these colors.',
        'action': 'add_theme_to_family',
      };
    }
    
    // Default case (no filters)
    return {
      'message': 'No color stories available right now. Check your connection or try again later.',
      'action': 'connection_issue',
    };
  }
  
  // Error handling is now done inline in the UI instead of global SnackBars
  
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Connection Error',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage.isNotEmpty ? _errorMessage : 'Unable to load color stories. Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _errorMessage = '';
                    });
                    _loadColorStories();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _errorMessage = '';
                      _stories = _getSampleStories();
                      _applyTextFilter();
                    });
                  },
                  icon: const Icon(Icons.preview),
                  label: const Text('View Samples'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  int _getGridCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 4; // Desktop
    if (width > 600) return 3;  // Tablet
    return 2;                   // Mobile
  }
}

class ColorStoryCard extends StatelessWidget {
  final ColorStory story;

  const ColorStoryCard({super.key, required this.story});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () {
          // Track story open analytics
          AnalyticsService.instance.trackColorStoryOpen(
            storyId: story.id,
            slug: story.slug,
            title: story.title,
            source: 'explore',
          );
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ColorStoryDetailScreen(colorStory: story),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Image with Palette Preview
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (story.heroImageUrl != null)
                    ClipRRect(
                      child: CachedNetworkImage(
                        imageUrl: story.heroImageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: Icon(
                              Icons.image_outlined,
                              size: 32,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[100],
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.broken_image_outlined,
                                size: 32,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Image unavailable',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    _buildPalettePreview(),
                  
                  // Featured badge
                  if (story.isFeatured)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Featured',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      semanticsLabel: story.title,
                    ),
                    const SizedBox(height: 4),
                    if (story.tags.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: story.tags.take(3).map((tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        )).toList(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPalettePreview() {
    if (story.palette.isEmpty) {
      return Container(
        color: Colors.grey[300],
        child: const Center(
          child: Icon(
            Icons.palette_outlined,
            size: 32,
            color: Colors.grey,
          ),
        ),
      );
    }

    return Row(
      children: story.palette.take(5).map((color) {
        final colorValue = int.parse(color.hex.substring(1), radix: 16) + 0xFF000000;
        return Expanded(
          child: Container(
            color: Color(colorValue),
          ),
        );
      }).toList(),
    );
  }
}