import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:color_canvas/utils/color_utils.dart';

// Brand model
class Brand {
  final String id;
  final String name;
  final String slug;
  final String? website;

  Brand({
    required this.id,
    required this.name,
    required this.slug,
    this.website,
  });

  factory Brand.fromJson(Map<String, dynamic> json, String id) {
    return Brand(
      id: id,
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
      website: json['website'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'slug': slug,
      'website': website,
    };
  }
}

// Paint model with CIELAB values
class Paint {
  final String id;
  final String brandId;
  final String brandName;
  final String name;
  final String code;
  final String hex;
  final List<int> rgb;
  final List<double> lab;
  final List<double> lch;
  final String? collection;
  final String? finish;
  final Map<String, dynamic>? metadata;

  Paint({
    required this.id,
    required this.brandId,
    required this.brandName,
    required this.name,
    required this.code,
    required this.hex,
    required this.rgb,
    required this.lab,
    required this.lch,
    this.collection,
    this.finish,
    this.metadata,
  });

  factory Paint.fromJson(Map<String, dynamic> json, String id) {
    return Paint(
      id: id,
      brandId: json['brandId'] ?? '',
      brandName: json['brandName'] ?? '',
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      hex: json['hex'] ?? '#000000',
      rgb: List<int>.from(json['rgb'] ?? [0, 0, 0]),
      lab: List<double>.from(json['lab'] ?? [0.0, 0.0, 0.0]),
      lch: List<double>.from(json['lch'] ?? [0.0, 0.0, 0.0]),
      collection: json['collection'],
      finish: json['finish'],
      metadata: json['metadata'],
    );
  }

  // Computed LRV (Light Reflectance Value) using LAB lightness or hex fallback
  double get computedLrv => lrvForPaint(paintLrv: null, hex: hex);

  Map<String, dynamic> toJson() {
    return {
      'brandId': brandId,
      'brandName': brandName,
      'name': name,
      'code': code,
      'hex': hex,
      'rgb': rgb,
      'lab': lab,
      'lch': lch,
      'collection': collection,
      'finish': finish,
      'metadata': metadata,
    };
  }
}

// Palette color with lock state
class PaletteColor {
  final String paintId;
  final bool locked;
  final int position;
  final String? brand;
  final String name;
  final String code;
  final String hex;

  PaletteColor({
    required this.paintId,
    required this.locked,
    required this.position,
    this.brand,
    required this.name,
    required this.code,
    required this.hex,
  });

  factory PaletteColor.fromJson(Map<String, dynamic> json) {
    return PaletteColor(
      paintId: json['paintId'] ?? '',
      locked: json['locked'] ?? false,
      position: json['position'] ?? 0,
      brand: json['brand'],
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      hex: json['hex'] ?? '#000000',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'paintId': paintId,
      'locked': locked,
      'position': position,
      'brand': brand,
      'name': name,
      'code': code,
      'hex': hex,
    };
  }

  Paint toPaint() {
    return Paint(
      id: paintId,
      brandId: brand ?? '',
      brandName: brand ?? '',
      name: name,
      code: code,
      hex: hex,
      rgb: ColorUtils.hexToRgb(hex),
      lab: ColorUtils.rgbToLab(
        ColorUtils.hexToRgb(hex)[0],
        ColorUtils.hexToRgb(hex)[1],
        ColorUtils.hexToRgb(hex)[2],
      ),
      lch: [0.0, 0.0, 0.0],
    );
  }
}

// User palette
class UserPalette {
  final String id;
  final String userId;
  final String name;
  final List<PaletteColor> colors;
  final List<String> tags;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserPalette({
    required this.id,
    required this.userId,
    required this.name,
    required this.colors,
    required this.tags,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserPalette.fromJson(Map<String, dynamic> json, String id) {
    return UserPalette(
      id: id,
      userId: json['userId'] ?? '',
      name: json['name'] ?? '',
      colors: (json['colors'] as List? ?? [])
          .map((color) => PaletteColor.fromJson(color))
          .toList(),
      tags: List<String>.from(json['tags'] ?? []),
      notes: json['notes'] ?? '',
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'name': name,
      'colors': colors.map((color) => color.toJson()).toList(),
      'tags': tags,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  UserPalette copyWith({
    String? id,
    String? userId,
    String? name,
    List<PaletteColor>? colors,
    List<String>? tags,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserPalette(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      colors: colors ?? this.colors,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// Share link
class ShareLink {
  final String id;
  final String paletteId;
  final String visibility; // 'private', 'unlisted', 'public'

  ShareLink({
    required this.id,
    required this.paletteId,
    required this.visibility,
  });

  factory ShareLink.fromJson(Map<String, dynamic> json, String id) {
    return ShareLink(
      id: id,
      paletteId: json['paletteId'] ?? '',
      visibility: json['visibility'] ?? 'private',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'paletteId': paletteId,
      'visibility': visibility,
    };
  }
}

// User favorite paint
class FavoritePaint {
  final String id;
  final String userId;
  final String paintId;
  final DateTime createdAt;

  FavoritePaint({
    required this.id,
    required this.userId,
    required this.paintId,
    required this.createdAt,
  });

  factory FavoritePaint.fromJson(Map<String, dynamic> json, String id) {
    return FavoritePaint(
      id: id,
      userId: json['userId'] ?? '',
      paintId: json['paintId'] ?? '',
      createdAt: (json['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'paintId': paintId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

// User copied paint data
class CopiedPaint {
  final String id;
  final String userId;
  final Paint paint;
  final DateTime createdAt;

  CopiedPaint({
    required this.id,
    required this.userId,
    required this.paint,
    required this.createdAt,
  });

  factory CopiedPaint.fromJson(Map<String, dynamic> json, String id) {
    return CopiedPaint(
      id: id,
      userId: json['userId'] ?? '',
      paint: Paint.fromJson(json['paint'], json['paint']['id'] ?? ''),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'paint': paint.toJson(),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

// Visualizer saved scene document
class VisualizerDoc {
  final String id;
  final String userId;
  final String roomId;
  final Map<String, dynamic> assignments; // surfaceType.name -> { paintId, finish }
  final double brightness; // -1..+1
  final double whiteBalanceK; // 2700..6500
  final String? style; // optional tag
  final DateTime createdAt;
  final DateTime updatedAt;

  VisualizerDoc({
    required this.id,
    required this.userId,
    required this.roomId,
    required this.assignments,
    required this.brightness,
    required this.whiteBalanceK,
    this.style,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VisualizerDoc.fromJson(Map<String, dynamic> json, String id) {
    return VisualizerDoc(
      id: id,
      userId: json['userId'] ?? '',
      roomId: json['roomId'] ?? 'living_room',
      assignments: Map<String, dynamic>.from(json['assignments'] ?? {}),
      brightness: (json['brightness'] ?? 0.0).toDouble(),
      whiteBalanceK: (json['whiteBalanceK'] ?? 4000.0).toDouble(),
      style: json['style'],
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'roomId': roomId,
      'assignments': assignments,
      'brightness': brightness,
      'whiteBalanceK': whiteBalanceK,
      'style': style,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}

// User profile
class UserProfile {
  final String id;
  final String email;
  final String displayName;
  final String plan;
  final int paletteCount;
  final bool isAdmin;
  final DateTime createdAt;

  UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.plan,
    required this.paletteCount,
    this.isAdmin = false,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json, String id) {
    return UserProfile(
      id: id,
      email: json['email'] ?? '',
      displayName: json['displayName'] ?? '',
      plan: json['plan'] ?? 'free',
      paletteCount: json['paletteCount'] ?? 0,
      isAdmin: json['isAdmin'] ?? false,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'displayName': displayName,
      'plan': plan,
      'paletteCount': paletteCount,
      'isAdmin': isAdmin,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

// Color Story palette item
class ColorStoryPalette {
  final String role; // main, accent, trim, ceiling, door, cabinet
  final String hex;
  final String? paintId;
  final String? brandName;
  final String? name;
  final String? code;
  final String? psychology;
  final String? usageTips;

  ColorStoryPalette({
    required this.role,
    required this.hex,
    this.paintId,
    this.brandName,
    this.name,
    this.code,
    this.psychology,
    this.usageTips,
  });

  factory ColorStoryPalette.fromJson(Map<String, dynamic> json) {
    return ColorStoryPalette(
      role: json['role'] ?? 'main',
      hex: json['hex'] ?? '#000000',
      paintId: json['paintId'],
      brandName: json['brandName'],
      name: json['name'],
      code: json['code'],
      psychology: json['psychology'],
      usageTips: json['usageTips'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'hex': hex,
      'paintId': paintId,
      'brandName': brandName,
      'name': name,
      'code': code,
      'psychology': psychology,
      'usageTips': usageTips,
    };
  }
}

// Color Story document
class ColorStory {
  final String id;
  final String title;
  final String slug;
  final String? heroImageUrl;
  final List<String> themes;
  final List<String> families;
  final List<String> rooms;
  final List<String> tags;
  final String description;
  final bool isFeatured;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ColorStoryPalette> palette;
  final List<String> facets; // Denormalized filter array for efficient ANDed queries

  ColorStory({
    required this.id,
    required this.title,
    required this.slug,
    this.heroImageUrl,
    required this.themes,
    required this.families,
    required this.rooms,
    required this.tags,
    required this.description,
    this.isFeatured = false,
    required this.createdAt,
    required this.updatedAt,
    required this.palette,
    required this.facets,
  });

  factory ColorStory.fromJson(Map<String, dynamic> json, String id) {
    return ColorStory(
      id: id,
      title: json['title'] ?? '',
      slug: json['slug'] ?? '',
      heroImageUrl: json['heroImageUrl'],
      themes: List<String>.from(json['themes'] ?? []),
      families: List<String>.from(json['families'] ?? []),
      rooms: List<String>.from(json['rooms'] ?? []),
      tags: List<String>.from(json['tags'] ?? []),
      description: json['description'] ?? '',
      isFeatured: json['isFeatured'] ?? false,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
      palette: (json['palette'] as List? ?? [])
          .map((item) => ColorStoryPalette.fromJson(item))
          .toList(),
      facets: List<String>.from(json['facets'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'slug': slug,
      'heroImageUrl': heroImageUrl,
      'themes': themes,
      'families': families,
      'rooms': rooms,
      'tags': tags,
      'description': description,
      'isFeatured': isFeatured,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'palette': palette.map((item) => item.toJson()).toList(),
      'facets': facets,
    };
  }

  ColorStory copyWith({
    String? id,
    String? title,
    String? slug,
    String? heroImageUrl,
    List<String>? themes,
    List<String>? families,
    List<String>? rooms,
    List<String>? tags,
    String? description,
    bool? isFeatured,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ColorStoryPalette>? palette,
    List<String>? facets,
  }) {
    return ColorStory(
      id: id ?? this.id,
      title: title ?? this.title,
      slug: slug ?? this.slug,
      heroImageUrl: heroImageUrl ?? this.heroImageUrl,
      themes: themes ?? this.themes,
      families: families ?? this.families,
      rooms: rooms ?? this.rooms,
      tags: tags ?? this.tags,
      description: description ?? this.description,
      isFeatured: isFeatured ?? this.isFeatured,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      palette: palette ?? this.palette,
      facets: facets ?? this.facets,
    );
  }
  
  /// Builds facets array from themes, families, and rooms for efficient querying
  static List<String> buildFacets({
    required List<String> themes,
    required List<String> families,
    required List<String> rooms,
  }) {
    final facets = <String>[];
    
    // Add theme facets
    for (final theme in themes) {
      facets.add('theme:$theme');
    }
    
    // Add family facets
    for (final family in families) {
      facets.add('family:$family');
    }
    
    // Add room facets
    for (final room in rooms) {
      facets.add('room:$room');
    }
    
    return facets;
  }
}