import 'dart:math' as math;
import 'package:color_canvas/firestore/firestore_data_schema.dart';
import 'package:color_canvas/utils/color_utils.dart';

enum HarmonyMode {
  neutral,
  analogous,
  complementary,
  triad,
  designer,
}

class PaletteGenerator {
  static final math.Random _random = math.Random();

  // Generate a dynamic-size palette with optional locked colors
  static List<Paint> rollPalette({
    required List<Paint> availablePaints,
    required List<Paint?> anchors, // dynamic length
    required HarmonyMode mode,
    bool diversifyBrands = true,
  }) {
    if (availablePaints.isEmpty) return [];
    
    final int size = anchors.length;
    final List<Paint?> result = List.filled(size, null, growable: false);
    
    // Copy locked anchors into result
    for (int i = 0; i < size; i++) {
      if (i < anchors.length && anchors[i] != null) {
        result[i] = anchors[i]!;
      }
    }
    
    // Seed paint: first locked or random
    Paint? seedPaint;
    for (final a in anchors) {
      if (a != null) { seedPaint = a; break; }
    }
    seedPaint ??= availablePaints[_random.nextInt(availablePaints.length)];
    
    // Add randomization factor to ensure different results on subsequent rolls
    final double randomOffset = _random.nextDouble() * 60 - 30; // ±30 degrees hue variation
    final double randomLightness = _random.nextDouble() * 20 - 10; // ±10 lightness variation
    
    // Get a base set of 5 targets, then remap to requested size
    final base5 = _generateHarmonyTargets(seedPaint.lab, mode, randomOffset, randomLightness);
    List<List<double>> targetLabs = _remapTargets(base5, size); // length == size

    // ✅ Only Designer is intentionally ordered (dark → light).
    // For all other modes, randomize the display order so it feels organic.
    if (mode != HarmonyMode.designer && targetLabs.length > 1) {
      final order = List<int>.generate(targetLabs.length, (i) => i)..shuffle(_random);
      targetLabs = order.map((idx) => targetLabs[idx]).toList(growable: false);
    }
    
    // --- NEW: compute per-slot LRV bands from locked anchors ---
    final List<double?> anchorLrv = List<double?>.filled(size, null);
    for (int i = 0; i < size; i++) {
      if (anchors[i] != null) {
        anchorLrv[i] = anchors[i]!.computedLrv;
      }
    }

    double minAvail = 100.0, maxAvail = 0.0;
    for (final p in availablePaints) {
      if (p.computedLrv < minAvail) minAvail = p.computedLrv;
      if (p.computedLrv > maxAvail) maxAvail = p.computedLrv;
    }

    // Descending LRV (index 0 = lightest/top)
    final List<double> minLrv = List<double>.filled(size, minAvail);
    final List<double> maxLrv = List<double>.filled(size, maxAvail);

    // Apply constraints from locked positions
    for (int j = 0; j < size; j++) {
      final lj = anchorLrv[j];
      if (lj == null) continue;
      // All indices ABOVE j must be >= lj
      for (int i = 0; i < j; i++) {
        if (minLrv[i] < lj) minLrv[i] = lj;
      }
      // All indices BELOW j must be <= lj
      for (int i = j + 1; i < size; i++) {
        if (maxLrv[i] > lj) maxLrv[i] = lj;
      }
    }

    // --- Fill unlocked positions with LRV-banded candidates ---
    final Set<String> usedBrands = <String>{};
    for (int i = 0; i < size; i++) {
      if (result[i] != null) {
        usedBrands.add(result[i]!.brandName);
        continue;
      }

      List<Paint> candidates = availablePaints;
      if (diversifyBrands && usedBrands.isNotEmpty) {
        final unused = availablePaints.where((p) => !usedBrands.contains(p.brandName)).toList();
        if (unused.isNotEmpty) candidates = unused;
      }

      // Start with a tight band; widen gradually if needed.
      double tol = 1.0; // LRV tolerance
      Paint? chosen;

      while (chosen == null && tol <= 10.0) {
        final low = minLrv[i] - tol;
        final high = maxLrv[i] + tol;

        // First, get harmony-near candidates
        final List<Paint> nearest = ColorUtils.nearestByDeltaEMultipleHueWindow(
          targetLabs[i], candidates, count: 12);

        // Apply band
        List<Paint> banded = nearest.where((p) {
          final l = p.computedLrv;
          return l >= low && l <= high;
        }).toList();

        // If still empty, widen band over the *full* candidate set
        if (banded.isEmpty) {
          banded = candidates.where((p) {
            final l = p.computedLrv;
            return l >= low && l <= high;
          }).toList()
          ..sort((a, b) {
            final da = ColorUtils.deltaE2000(targetLabs[i], a.lab);
            final db = ColorUtils.deltaE2000(targetLabs[i], b.lab);
            return da.compareTo(db);
          });
        }

        if (banded.isNotEmpty) {
          // Keep some variation; don't always take 0th
          final pick = banded.length <= 5 ? banded.length : 5;
          chosen = banded[_random.nextInt(pick)];
        } else {
          tol += 2.0; // widen and try again
        }
      }

      if (chosen != null) {
        result[i] = chosen;
        usedBrands.add(chosen.brandName);
      }
    }
    
    // All non-null by construction, but cast defensively
    return result.whereType<Paint>().toList(growable: false);
  }

  // Generate target LAB values based on harmony mode
  static List<List<double>> _generateHarmonyTargets(List<double> seedLab, HarmonyMode mode, 
      [double randomHueOffset = 0, double randomLightnessOffset = 0]) {
    final List<List<double>> targets = [];
    final seedLch = ColorUtils.labToLch(seedLab[0], seedLab[1], seedLab[2]);
    final double baseLightness = seedLch[0] + randomLightnessOffset;
    final double baseChroma = seedLch[1];
    final double baseHue = seedLch[2] + randomHueOffset;
    
    switch (mode) {
      case HarmonyMode.neutral:
        targets.addAll(_generateNeutralTargets(baseLightness, baseChroma, baseHue));
        break;
      case HarmonyMode.analogous:
        targets.addAll(_generateAnalogousTargets(baseLightness, baseChroma, baseHue));
        break;
      case HarmonyMode.complementary:
        targets.addAll(_generateComplementaryTargets(baseLightness, baseChroma, baseHue));
        break;
      case HarmonyMode.triad:
        targets.addAll(_generateTriadTargets(baseLightness, baseChroma, baseHue));
        break;
      case HarmonyMode.designer:
        targets.addAll(_generateDesignerTargets(baseLightness, baseChroma, baseHue));
        break;
    }
    
    return targets;
  }

  // Generate neutral blend targets
  static List<List<double>> _generateNeutralTargets(double l, double c, double h) {
    final List<List<double>> targets = [];
    
    // Create a range of lightness values with subtle hue shifts
    final List<double> lightnessSteps = [
      math.max(20, l - 30),
      math.max(10, l - 15),
      l,
      math.min(90, l + 15),
      math.min(95, l + 30),
    ];
    
    for (int i = 0; i < 5; i++) {
      final double targetL = lightnessSteps[i];
      final double targetC = math.max(5, c * (0.3 + 0.1 * i)); // Reduce chroma for neutrals
      final double targetH = (h + (i - 2) * 10) % 360; // Subtle hue shift
      
      targets.add(_lchToLab(targetL, targetC, targetH));
    }
    
    return targets;
  }

  // Generate analogous harmony targets
  static List<List<double>> _generateAnalogousTargets(double l, double c, double h) {
    final List<List<double>> targets = [];
    
    for (int i = 0; i < 5; i++) {
      final double targetL = l + (i - 2) * 10; // Vary lightness
      final double targetC = c * (0.7 + 0.1 * i); // Slightly vary chroma
      final double targetH = (h + (i - 2) * 30) % 360; // ±60° hue range
      
      targets.add(_lchToLab(math.max(0, math.min(100, targetL)), math.max(0, targetC), targetH));
    }
    
    return targets;
  }

  // Generate complementary harmony targets
  static List<List<double>> _generateComplementaryTargets(double l, double c, double h) {
    final List<List<double>> targets = [];
    final double complementH = (h + 180) % 360;
    
    // Mix of original and complementary hues
    final List<double> hues = [h, h, complementH, complementH, (h + complementH) / 2];
    
    for (int i = 0; i < 5; i++) {
      final double targetL = l + (i - 2) * 8;
      final double targetC = c * (0.8 + 0.1 * (i % 2));
      final double targetH = hues[i];
      
      targets.add(_lchToLab(math.max(0, math.min(100, targetL)), math.max(0, targetC), targetH));
    }
    
    return targets;
  }

  // Generate triad harmony targets
  static List<List<double>> _generateTriadTargets(double l, double c, double h) {
    final List<List<double>> targets = [];
    final List<double> hues = [h, (h + 120) % 360, (h + 240) % 360, h, (h + 60) % 360];
    
    for (int i = 0; i < 5; i++) {
      final double targetL = l + (i - 2) * 8;
      final double targetC = c * (0.7 + 0.15 * (i % 2));
      final double targetH = hues[i];
      
      targets.add(_lchToLab(math.max(0, math.min(100, targetL)), math.max(0, targetC), targetH));
    }
    
    return targets;
  }

  // Generate designer harmony targets with LRV bands
  static List<List<double>> _generateDesignerTargets(double seedL, double seedC, double seedH) {
    final List<List<double>> targets = [];
    
    // Fixed LRV (lightness) bands for Designer mode (ordered dark to light)
    // Anchor: 0-15, Secondary: 30-55, Bridge: 50-65, Dominant: 55-70, Whisper: 75-92
    final List<double> designerLightness = [12, 42, 57, 65, 83]; // Mid-points of each band
    
    // Hue relationships based on seed hue
    final List<double> designerHues = [
      seedH,                    // Anchor: original hue
      (seedH + 30) % 360,      // Secondary: +30° 
      (seedH + 170) % 360,     // Bridge: +170° (soft complement)
      seedH,                   // Dominant: original hue
      (seedH + 15) % 360,      // Whisper: +15° (subtle shift)
    ];
    
    // Chroma adjustments for each role
    final List<double> chromaMultipliers = [
      0.8, // Anchor: strong but not overpowering
      0.9, // Secondary: high chroma for interest
      0.4, // Bridge: low chroma to connect colors
      0.7, // Dominant: moderate chroma
      0.3, // Whisper: very low chroma
    ];
    
    for (int i = 0; i < 5; i++) {
      final double targetL = designerLightness[i];
      final double targetC = math.max(5, seedC * chromaMultipliers[i]);
      final double targetH = designerHues[i];
      
      targets.add(_lchToLab(targetL, targetC, targetH));
    }
    
    return targets;
  }

  // Remap base 5 targets to any size (1-9)
  static List<List<double>> _remapTargets(List<List<double>> base5, int size) {
    if (size <= 0) return const [];
    if (size == 5) return base5;

    // Edge cases: 1 → pick the middle, 2 → ends, else sample evenly
    final List<List<double>> out = [];
    if (size == 1) {
      out.add(base5[2]);
      return out;
    }
    if (size == 2) {
      out.add(base5.first);
      out.add(base5.last);
      return out;
    }

    for (int i = 0; i < size; i++) {
      final double t = (size == 1) ? 0 : i * (base5.length - 1) / (size - 1);
      final int idx = t.round().clamp(0, base5.length - 1);
      out.add(base5[idx]);
    }
    return out;
  }

  // Convert LCH to LAB
  static List<double> _lchToLab(double l, double c, double h) {
    final double hRad = h * math.pi / 180;
    final double a = c * math.cos(hRad);
    final double b = c * math.sin(hRad);
    return [l, a, b];
  }

  // Find paint with slightly higher hue (next hue up)
  static Paint? nudgeLighter(Paint paint, List<Paint> availablePaints) {
    final currentLch = ColorUtils.labToLch(paint.lab[0], paint.lab[1], paint.lab[2]);
    final currentHue = currentLch[2];
    
    // Find paints with slightly higher hue (up to +45 degrees)
    final candidates = availablePaints
        .where((p) => p.id != paint.id)
        .map((p) {
          final lch = ColorUtils.labToLch(p.lab[0], p.lab[1], p.lab[2]);
          final hue = lch[2];
          
          // Calculate hue difference (handling wraparound)
          double hueDiff = hue - currentHue;
          if (hueDiff < 0) hueDiff += 360;
          if (hueDiff > 180) hueDiff -= 360;
          
          return {'paint': p, 'hueDiff': hueDiff, 'lch': lch};
        })
        .where((data) => data['hueDiff'] as double > 0 && data['hueDiff'] as double <= 45)
        .toList();
    
    if (candidates.isEmpty) return null;
    
    // Sort by closest hue difference, then by lightness similarity
    candidates.sort((a, b) {
      final hueDiffA = (a['hueDiff'] as double).abs();
      final hueDiffB = (b['hueDiff'] as double).abs();
      if (hueDiffA != hueDiffB) return hueDiffA.compareTo(hueDiffB);
      
      // If hue difference is similar, prefer similar lightness
      final lchA = a['lch'] as List<double>;
      final lchB = b['lch'] as List<double>;
      final lightnessDiffA = (lchA[0] - currentLch[0]).abs();
      final lightnessDiffB = (lchB[0] - currentLch[0]).abs();
      return lightnessDiffA.compareTo(lightnessDiffB);
    });
    
    return candidates.first['paint'] as Paint;
  }

  // Find paint with slightly lower hue (next hue down)
  static Paint? nudgeDarker(Paint paint, List<Paint> availablePaints) {
    final currentLch = ColorUtils.labToLch(paint.lab[0], paint.lab[1], paint.lab[2]);
    final currentHue = currentLch[2];
    
    // Find paints with slightly lower hue (down to -45 degrees)
    final candidates = availablePaints
        .where((p) => p.id != paint.id)
        .map((p) {
          final lch = ColorUtils.labToLch(p.lab[0], p.lab[1], p.lab[2]);
          final hue = lch[2];
          
          // Calculate hue difference (handling wraparound)
          double hueDiff = hue - currentHue;
          if (hueDiff < -180) hueDiff += 360;
          if (hueDiff > 180) hueDiff -= 360;
          
          return {'paint': p, 'hueDiff': hueDiff, 'lch': lch};
        })
        .where((data) => data['hueDiff'] as double < 0 && data['hueDiff'] as double >= -45)
        .toList();
    
    if (candidates.isEmpty) return null;
    
    // Sort by closest hue difference, then by lightness similarity
    candidates.sort((a, b) {
      final hueDiffA = (a['hueDiff'] as double).abs();
      final hueDiffB = (b['hueDiff'] as double).abs();
      if (hueDiffA != hueDiffB) return hueDiffA.compareTo(hueDiffB);
      
      // If hue difference is similar, prefer similar lightness
      final lchA = a['lch'] as List<double>;
      final lchB = b['lch'] as List<double>;
      final lightnessDiffA = (lchA[0] - currentLch[0]).abs();
      final lightnessDiffB = (lchB[0] - currentLch[0]).abs();
      return lightnessDiffA.compareTo(lightnessDiffB);
    });
    
    return candidates.first['paint'] as Paint;
  }

  // Swap to different brand with similar color
  static Paint? swapBrand(Paint paint, List<Paint> availablePaints, {double threshold = 10.0}) {
    final otherBrandPaints = availablePaints
        .where((p) => p.brandName != paint.brandName)
        .toList();
    
    if (otherBrandPaints.isEmpty) return null;
    
    // Find paints within Delta E threshold
    final similarPaints = otherBrandPaints.where((p) {
      final deltaE = ColorUtils.deltaE2000(paint.lab, p.lab);
      return deltaE <= threshold;
    }).toList();
    
    if (similarPaints.isEmpty) {
      // Return nearest if no close match
      return ColorUtils.nearestByDeltaE(paint.lab, otherBrandPaints);
    }
    
    // Return closest match within threshold
    similarPaints.sort((a, b) {
      final deltaA = ColorUtils.deltaE2000(paint.lab, a.lab);
      final deltaB = ColorUtils.deltaE2000(paint.lab, b.lab);
      return deltaA.compareTo(deltaB);
    });
    
    return similarPaints.first;
  }

}