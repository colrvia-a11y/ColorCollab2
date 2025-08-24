import 'dart:math' as math;
import 'package:flutter/material.dart' hide Paint;
import 'package:color_canvas/firestore/firestore_data_schema.dart';

// LRV (Light Reflectance Value) cache for performance
class LrvCache {
  static final Map<String, double> _cache = {};
  
  static double getForHex(String hex) {
    final key = hex.toUpperCase();
    if (_cache.containsKey(key)) return _cache[key]!;
    final c = _hexToColorSafe(hex);
    final lrv = _computeLrv(c);
    _cache[key] = lrv;
    return lrv;
  }

  static Color _hexToColorSafe(String hex) {
    var h = hex.trim();
    if (!h.startsWith('#')) h = '#$h';
    if (h.length == 4) { // #RGB → #RRGGBB
      h = '#${h[1]}${h[1]}${h[2]}${h[2]}${h[3]}${h[3]}';
    }
    try {
      return Color(int.parse(h.substring(1), radix: 16) + 0xFF000000);
    } catch (_) {
      return const Color(0xFF000000); // fallback black if bad input
    }
  }

  static double _computeLrv(Color c) {
    // sRGB → linear
    double toLin(int ch) {
      final cs = ch / 255.0;
      return cs <= 0.04045 ? (cs / 12.92) : math.pow((cs + 0.055) / 1.055, 2.4).toDouble();
    }
    final r = toLin(c.red), g = toLin(c.green), b = toLin(c.blue);
    final y = 0.2126 * r + 0.7152 * g + 0.0722 * b; // relative luminance
    return (y * 100.0).clamp(0.0, 100.0);
  }
}

// Convenience function for getting LRV
double lrvForPaint({double? paintLrv, String? hex}) {
  if (paintLrv != null && paintLrv > 0) return paintLrv.clamp(0, 100);
  if (hex != null && hex.isNotEmpty) return LrvCache.getForHex(hex);
  return 0.0;
}

// Color conversion utilities
class ColorUtils {
  // Normalize hex string to handle various formats
  static String _normalizeHex(String? input) {
    if (input == null) return '';
    var s = input.trim();

    // Strip common prefixes
    if (s.startsWith('#')) s = s.substring(1);
    if (s.toLowerCase().startsWith('0x')) s = s.substring(2);

    // Keep only hex chars
    s = s.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');

    // Handle ARGB/AARRGGBB by dropping leading alpha
    if (s.length == 8) s = s.substring(2);
    if (s.length == 4) s = s.substring(1).split('').map((c) => c + c).join();

    // Expand #RGB
    if (s.length == 3) s = s.split('').map((c) => c + c).join();

    // If longer than 6, take the last 6 (RRGGBB)
    if (s.length > 6) s = s.substring(s.length - 6);

    // Pad to 6
    return s.padLeft(6, '0').toUpperCase();
  }

  // Helper to convert hex string to Color
  static Color _fromHex(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }

  // Convert Paint hex to Flutter Color
  static Color getPaintColor(Paint? paint) {
    if (paint == null) return Colors.grey[300]!;
    
    final hex = _normalizeHex(paint.hex);
    if (hex.isEmpty) return Colors.grey[300]!;
    
    try {
      return _fromHex(hex);
    } catch (e) {
      return Colors.grey[300]!;
    }
  }

  // Convert hex string to Flutter Color
  static Color hexToColor(String hex) {
    final norm = _normalizeHex(hex);
    if (norm.isEmpty) return Colors.grey[300]!;
    try {
      return _fromHex(norm);
    } catch (e) {
      return Colors.grey[300]!;
    }
  }

  // Convert hex to RGB
  static List<int> hexToRgb(String hex) {
    final norm = _normalizeHex(hex);
    final value = int.tryParse(norm, radix: 16);
    if (value == null) return [0, 0, 0];
    return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF];
  }

  // Convert RGB to XYZ color space
  static List<double> rgbToXyz(int r, int g, int b) {
    double rNorm = r / 255.0;
    double gNorm = g / 255.0;
    double bNorm = b / 255.0;

    // Gamma correction
    rNorm = rNorm > 0.04045 
        ? math.pow((rNorm + 0.055) / 1.055, 2.4).toDouble()
        : rNorm / 12.92;
    gNorm = gNorm > 0.04045 
        ? math.pow((gNorm + 0.055) / 1.055, 2.4).toDouble()
        : gNorm / 12.92;
    bNorm = bNorm > 0.04045 
        ? math.pow((bNorm + 0.055) / 1.055, 2.4).toDouble()
        : bNorm / 12.92;

    rNorm *= 100;
    gNorm *= 100;
    bNorm *= 100;

    // Observer = 2°, Illuminant = D65
    final double x = rNorm * 0.4124 + gNorm * 0.3576 + bNorm * 0.1805;
    final double y = rNorm * 0.2126 + gNorm * 0.7152 + bNorm * 0.0722;
    final double z = rNorm * 0.0193 + gNorm * 0.1192 + bNorm * 0.9505;

    return [x, y, z];
  }

  // Convert XYZ to CIELAB
  static List<double> xyzToLab(double x, double y, double z) {
    // Reference white D65
    const double xn = 95.047;
    const double yn = 100.000;
    const double zn = 108.883;

    double xr = x / xn;
    double yr = y / yn;
    double zr = z / zn;

    // Apply function f(t)
    final double fx = xr > 0.008856 
        ? math.pow(xr, 1.0 / 3.0).toDouble()
        : (7.787 * xr + 16.0 / 116.0);
    final double fy = yr > 0.008856 
        ? math.pow(yr, 1.0 / 3.0).toDouble()
        : (7.787 * yr + 16.0 / 116.0);
    final double fz = zr > 0.008856 
        ? math.pow(zr, 1.0 / 3.0).toDouble()
        : (7.787 * zr + 16.0 / 116.0);

    final double l = 116.0 * fy - 16.0;
    final double a = 500.0 * (fx - fy);
    final double b = 200.0 * (fy - fz);

    return [l, a, b];
  }

  // Convert RGB to CIELAB
  static List<double> rgbToLab(int r, int g, int b) {
    final xyz = rgbToXyz(r, g, b);
    return xyzToLab(xyz[0], xyz[1], xyz[2]);
  }

  // Convert LAB to LCH
  static List<double> labToLch(double l, double a, double b) {
    final double c = math.sqrt(a * a + b * b);
    double h = math.atan2(b, a) * 180.0 / math.pi;
    if (h < 0) h += 360;
    return [l, c, h];
  }

  // Delta E 2000 color difference calculation
  static double deltaE2000(List<double> lab1, List<double> lab2) {
    final double l1 = lab1[0], a1 = lab1[1], b1 = lab1[2];
    final double l2 = lab2[0], a2 = lab2[1], b2 = lab2[2];

    final double c1 = math.sqrt(a1 * a1 + b1 * b1);
    final double c2 = math.sqrt(a2 * a2 + b2 * b2);
    final double cMean = (c1 + c2) / 2.0;

    final double g = 0.5 * (1 - math.sqrt(math.pow(cMean, 7) / (math.pow(cMean, 7) + math.pow(25, 7))));
    
    final double a1Prime = a1 * (1 + g);
    final double a2Prime = a2 * (1 + g);
    
    final double c1Prime = math.sqrt(a1Prime * a1Prime + b1 * b1);
    final double c2Prime = math.sqrt(a2Prime * a2Prime + b2 * b2);
    
    final double h1Prime = math.atan2(b1, a1Prime) * 180 / math.pi;
    final double h2Prime = math.atan2(b2, a2Prime) * 180 / math.pi;

    final double deltaL = l2 - l1;
    final double deltaC = c2Prime - c1Prime;
    
    double deltaH = h2Prime - h1Prime;
    if (deltaH.abs() > 180) {
      deltaH = deltaH > 180 ? deltaH - 360 : deltaH + 360;
    }
    
    final double deltaHPrime = 2 * math.sqrt(c1Prime * c2Prime) * math.sin(deltaH * math.pi / 360);

    final double lMean = (l1 + l2) / 2;
    final double cMeanPrime = (c1Prime + c2Prime) / 2;
    
    double hMeanPrime = (h1Prime + h2Prime) / 2;
    if ((h1Prime - h2Prime).abs() > 180) {
      hMeanPrime = hMeanPrime < 180 ? hMeanPrime + 180 : hMeanPrime - 180;
    }

    final double t = 1 - 0.17 * math.cos((hMeanPrime - 30) * math.pi / 180) +
                     0.24 * math.cos(2 * hMeanPrime * math.pi / 180) +
                     0.32 * math.cos((3 * hMeanPrime + 6) * math.pi / 180) -
                     0.20 * math.cos((4 * hMeanPrime - 63) * math.pi / 180);

    final double deltaTheta = 30 * math.exp(-math.pow((hMeanPrime - 275) / 25, 2));
    final double rc = 2 * math.sqrt(math.pow(cMeanPrime, 7) / (math.pow(cMeanPrime, 7) + math.pow(25, 7)));
    final double sl = 1 + ((0.015 * math.pow(lMean - 50, 2)) / math.sqrt(20 + math.pow(lMean - 50, 2)));
    final double sc = 1 + 0.045 * cMeanPrime;
    final double sh = 1 + 0.015 * cMeanPrime * t;
    final double rt = -math.sin(2 * deltaTheta * math.pi / 180) * rc;

    final double kl = 1, kc = 1, kh = 1;

    final double deltaE = math.sqrt(
      math.pow(deltaL / (kl * sl), 2) +
      math.pow(deltaC / (kc * sc), 2) +
      math.pow(deltaHPrime / (kh * sh), 2) +
      rt * (deltaC / (kc * sc)) * (deltaHPrime / (kh * sh))
    );

    return deltaE;
  }

  // Find nearest paint by Delta E
  static Paint? nearestByDeltaE(List<double> targetLab, List<Paint> paints) {
    if (paints.isEmpty) return null;
    
    Paint? nearest;
    double minDeltaE = double.infinity;
    
    for (final paint in paints) {
      final double deltaE = deltaE2000(targetLab, paint.lab);
      if (deltaE < minDeltaE) {
        minDeltaE = deltaE;
        nearest = paint;
      }
    }
    
    return nearest;
  }

  // Find multiple nearest paints by Delta E for randomization
  static List<Paint> nearestByDeltaEMultiple(List<double> targetLab, List<Paint> paints, {int count = 5}) {
    if (paints.isEmpty) return [];
    
    final List<MapEntry<Paint, double>> paintDistances = [];
    
    for (final paint in paints) {
      final double deltaE = deltaE2000(targetLab, paint.lab);
      paintDistances.add(MapEntry(paint, deltaE));
    }
    
    // Sort by Delta E distance
    paintDistances.sort((a, b) => a.value.compareTo(b.value));
    
    // Return the top N closest paints
    return paintDistances
        .take(math.min(count, paintDistances.length))
        .map((entry) => entry.key)
        .toList();
  }

  // Optimized version with hue windowing for better performance
  static List<Paint> nearestByDeltaEMultipleHueWindow(List<double> targetLab, List<Paint> paints, {int count = 5}) {
    if (paints.isEmpty) return [];
    
    // Convert target LAB to LCH to get hue
    final targetLch = labToLch(targetLab[0], targetLab[1], targetLab[2]);
    final targetHue = targetLch[2];
    
    // Filter paints within ±90° hue window for performance
    final List<Paint> hueFiltered = [];
    for (final paint in paints) {
      final paintHue = paint.lch[2];
      double hueDiff = (paintHue - targetHue).abs();
      if (hueDiff > 180) hueDiff = 360 - hueDiff;
      
      if (hueDiff <= 90) {
        hueFiltered.add(paint);
      }
    }
    
    // If hue filtering removed too many candidates, fall back to full search
    final candidates = hueFiltered.length >= count * 2 ? hueFiltered : paints;
    
    final List<MapEntry<Paint, double>> paintDistances = [];
    
    for (final paint in candidates) {
      final double deltaE = deltaE2000(targetLab, paint.lab);
      paintDistances.add(MapEntry(paint, deltaE));
    }
    
    // Sort by Delta E distance
    paintDistances.sort((a, b) => a.value.compareTo(b.value));
    
    // Return the top N closest paints
    return paintDistances
        .take(math.min(count, paintDistances.length))
        .map((entry) => entry.key)
        .toList();
  }

  // Get undertone tags based on hue angle
  static List<String> undertoneTags(List<double> lab) {
    final lch = labToLch(lab[0], lab[1], lab[2]);
    final double hue = lch[2];
    final double chroma = lch[1];
    
    final List<String> tags = [];
    
    // Only add undertone tags if there's sufficient chroma
    if (chroma < 10) {
      tags.add('neutral');
      return tags;
    }
    
    // Hue-based undertones
    if (hue >= 345 || hue < 15) {
      tags.add('red');
    } else if (hue >= 15 && hue < 45) {
      tags.add('orange');
    } else if (hue >= 45 && hue < 75) {
      tags.add('yellow');
    } else if (hue >= 75 && hue < 165) {
      tags.add('green');
    } else if (hue >= 165 && hue < 255) {
      tags.add('blue');
    } else if (hue >= 255 && hue < 285) {
      tags.add('purple');
    } else if (hue >= 285 && hue < 315) {
      tags.add('magenta');
    } else {
      tags.add('pink');
    }
    
    // Warmth indicators
    if ((hue >= 315 || hue < 135) && chroma > 15) {
      tags.add('warm');
    } else if (hue >= 135 && hue < 315 && chroma > 15) {
      tags.add('cool');
    }
    
    return tags;
  }

  // Calculate relative luminance for accessibility
  static double _luminance(Color c) {
    final r = c.red / 255.0, g = c.green / 255.0, b = c.blue / 255.0;
    double lin(double x) => x <= 0.03928 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
    final L = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
    return L;
  }

  // Determine optimal text color for background with WCAG contrast
  static Color preferredTextColor(Color bg) {
    // Compare contrast to white vs black; pick higher
    final white = Colors.white, black = Colors.black;
    double contrast(Color fg) {
      final L1 = math.max(_luminance(fg), _luminance(bg));
      final L2 = math.min(_luminance(fg), _luminance(bg));
      return (L1 + 0.05) / (L2 + 0.05);
    }
    return contrast(black) >= contrast(white) ? black : white;
  }

  // Check if color is light (for determining text color) - kept for backward compatibility
  static bool isLightColor(Color color) {
    return _luminance(color) > 0.5;
  }

  // Create accessible tinted background with capped opacity
  static Color createAccessibleTintedBackground(Color baseColor, Color tintColor, {double maxOpacity = 0.08}) {
    // Cap the tint opacity to ensure readability
    final cappedOpacity = math.min(maxOpacity, 0.08);
    return Color.lerp(baseColor, tintColor, cappedOpacity) ?? baseColor;
  }

  // Complete color processing for paint import
  static Map<String, dynamic> processColor(String hex) {
    final rgb = hexToRgb(hex);
    final lab = rgbToLab(rgb[0], rgb[1], rgb[2]);
    final lch = labToLch(lab[0], lab[1], lab[2]);
    
    return {
      'rgb': rgb,
      'lab': lab,
      'lch': lch,
    };
  }

  /// Converts ColorStory palette to Paint objects for use in Roller
  static List<Paint> colorStoryPaletteToPaints(List<ColorStoryPalette> palette) {
    final List<Paint> paints = [];
    final Set<String> usedIds = {};
    
    // Role priority order for consistent positioning
    const roleOrder = ['main', 'accent', 'trim', 'ceiling', 'door', 'cabinet'];
    
    // Sort palette by role priority, then original order
    final sortedPalette = List<ColorStoryPalette>.from(palette);
    sortedPalette.sort((a, b) {
      final aIndex = roleOrder.indexOf(a.role);
      final bIndex = roleOrder.indexOf(b.role);
      final aPriority = aIndex == -1 ? roleOrder.length : aIndex;
      final bPriority = bIndex == -1 ? roleOrder.length : bIndex;
      return aPriority.compareTo(bPriority);
    });
    
    for (final paletteItem in sortedPalette) {
      // Skip duplicates by paintId or hex
      final identifier = paletteItem.paintId ?? paletteItem.hex;
      if (usedIds.contains(identifier)) continue;
      usedIds.add(identifier);
      
      // Convert to Paint object
      final paint = _colorStoryPaletteToPaint(paletteItem);
      paints.add(paint);
    }
    
    return paints;
  }

  /// Converts a single ColorStoryPalette to Paint object
  static Paint _colorStoryPaletteToPaint(ColorStoryPalette paletteItem) {
    // Generate synthetic ID if paintId is missing
    final paintId = paletteItem.paintId ?? 'synthetic_${paletteItem.hex.replaceAll('#', '')}';
    
    // Compute color values from hex
    final rgb = hexToRgb(paletteItem.hex);
    final lab = rgbToLab(rgb[0], rgb[1], rgb[2]);
    final lch = labToLch(lab[0], lab[1], lab[2]);
    
    return Paint(
      id: paintId,
      brandId: paletteItem.brandName?.toLowerCase().replaceAll(' ', '_') ?? 'unknown',
      brandName: paletteItem.brandName ?? 'Custom',
      name: paletteItem.name ?? 'Color ${paletteItem.role}',
      code: paletteItem.code ?? paletteItem.hex,
      hex: paletteItem.hex,
      rgb: rgb,
      lab: lab,
      lch: lch,
      collection: null,
      finish: null,
      metadata: {
        'role': paletteItem.role,
        'psychology': paletteItem.psychology,
        'usageTips': paletteItem.usageTips,
        'source': 'color_story',
      },
    );
  }

  /// Determines the optimal palette size based on Color Story palette length
  static int getOptimalPaletteSizeForColorStory(List<ColorStoryPalette> palette) {
    final length = palette.length;
    // Clamp to Roller's supported range (1-5)
    return math.max(1, math.min(5, length));
  }
}