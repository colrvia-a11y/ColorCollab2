import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:color_canvas/utils/color_utils.dart';
import 'package:color_canvas/firestore/firestore_data_schema.dart' as schema;
import 'package:color_canvas/services/firebase_service.dart';
import 'package:color_canvas/models/visualizer_models.dart';

class VisualizerScreen extends StatefulWidget {
  const VisualizerScreen({super.key});
  @override
  State<VisualizerScreen> createState() => _VisualizerScreenState();
}

class _VisualizerScreenState extends State<VisualizerScreen> {
  String _roomId = 'living_room';
  RoomTemplate get _room => kRoomTemplates[_roomId]!;
  final ScreenshotController _shot = ScreenshotController();

  // surface -> state
  final Map<SurfaceType, SurfaceState> _assignments = {
    for (final s in livingRoomTemplate.surfaces) s.type: const SurfaceState(),
  };

  // UI state
  SurfaceType? _selectedSurface;
  double _brightness = 0.0;      // -1..+1
  double _whiteBalanceK = 4000;  // 2700..6500
  String? _styleTag;

  // History
  final List<Map<SurfaceType, SurfaceState>> _undo = [];
  final List<Map<SurfaceType, SurfaceState>> _redo = [];

  // Snapshots (quick A/B)
  final List<Map<SurfaceType, SurfaceState>> _snapshots = [];

  // Paint search
  final TextEditingController _searchCtl = TextEditingController();
  List<schema.Paint> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadRecentPaletteIntoWalls(); // nice first impression
  }

  Future<void> _loadRecentPaletteIntoWalls() async {
    try {
      final recent = await FirebaseService.getMostRecentUserPalette();
      if (recent == null || recent.colors.isEmpty) return;
      // smart-ish defaults
      final wall = recent.colors.first.toPaint();
      final trim = recent.colors.length > 1 ? recent.colors[1].toPaint() : null;
      final accent = recent.colors.length > 2 ? recent.colors[2].toPaint() : null;

      setState(() {
        _assignments[SurfaceType.backWall] = _assignments[SurfaceType.backWall]!.copyWith(paint: wall);
        if (trim != null) {
          _assignments[SurfaceType.trim] = _assignments[SurfaceType.trim]!.copyWith(paint: trim, finish: Finish.semiGloss);
        }
        if (accent != null) {
          _assignments[SurfaceType.sofa] = _assignments[SurfaceType.sofa]!.copyWith(paint: accent, finish: Finish.matte);
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  // ----- History helpers -----
  void _pushHistory() {
    _undo.add(_cloneAssignments(_assignments));
    _redo.clear();
  }

  Map<SurfaceType, SurfaceState> _cloneAssignments(Map<SurfaceType, SurfaceState> src) {
    return {
      for (final e in src.entries) e.key: SurfaceState(paint: e.value.paint, finish: e.value.finish),
    };
  }

  void _undoAction() {
    if (_undo.isEmpty) return;
    _redo.add(_cloneAssignments(_assignments));
    final prev = _undo.removeLast();
    setState(() {
      _assignments
        ..clear()
        ..addAll(prev);
    });
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    _undo.add(_cloneAssignments(_assignments));
    final next = _redo.removeLast();
    setState(() {
      _assignments
        ..clear()
        ..addAll(next);
    });
  }

  // ----- Paint picking -----
  Future<void> _searchPaints(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _isSearching = true);
    try {
      _searchResults = await FirebaseService.searchPaints(q.trim());
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _applyPaintToSelected(schema.Paint paint) {
    if (_selectedSurface == null) return;
    _pushHistory();
    setState(() {
      final prev = _assignments[_selectedSurface] ?? const SurfaceState();
      _assignments[_selectedSurface!] = prev.copyWith(paint: paint);
    });
  }

  // ----- Finish per surface -----
  void _changeFinish(Finish finish) {
    if (_selectedSurface == null) return;
    _pushHistory();
    setState(() {
      final prev = _assignments[_selectedSurface] ?? const SurfaceState();
      _assignments[_selectedSurface!] = prev.copyWith(finish: finish);
    });
  }

  // ----- Lighting -----
  Color _applyLighting(Color c) {
    // brightness: simple scale in HSL lightness
    HSLColor hsl = HSLColor.fromColor(c);
    double l = (hsl.lightness + _brightness * 0.25).clamp(0.0, 1.0);
    Color bright = hsl.withLightness(l).toColor();

    // white balance: warm < 4000K adds warm tint; cool > 4000K adds cool tint
    if (_whiteBalanceK < 4000) {
      final warm = const Color(0xFFFFE3C4); // warm ambient
      return Color.alphaBlend(warm.withValues(alpha: _wbAmount()), bright);
    } else if (_whiteBalanceK > 4000) {
      final cool = const Color(0xFFCFE4FF); // cool ambient
      return Color.alphaBlend(cool.withValues(alpha: _wbAmount()), bright);
    }
    return bright;
  }

  double _wbAmount() {
    // map 2700..6500 to 0..0.22
    final d = (_whiteBalanceK - 4000).abs();
    return (math.min(1.0, d / 2500.0)) * 0.22;
    }

  // ----- Export (PNG + PDF) -----
  Future<void> _exportPng() async {
    final bytes = await _shot.capture(pixelRatio: 2.0);
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = await File('${dir.path}/visualizer_${DateTime.now().millisecondsSinceEpoch}.png').create();
    await file.writeAsBytes(bytes);
    // share
    await Share.shareXFiles([XFile(file.path)], text: 'Room Visualizer');
  }

  Future<void> _exportSpecPdf() async {
    final doc = pw.Document();
    final surfaceRows = _room.surfaces.map((s) {
      final st = _assignments[s.type];
      final p = st?.paint;
      return [
        s.label,
        p?.brandName ?? '-',
        p?.name ?? '-',
        p?.code ?? '-',
        p?.hex ?? '-',
        (st?.finish ?? Finish.eggshell).name,
      ];
    }).toList();

    doc.addPage(
      pw.MultiPage(
        build: (c) => [
          pw.Text('Room Spec — ${_room.name}', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Lighting: brightness ${_brightness.toStringAsFixed(2)}, white balance ${_whiteBalanceK.round()}K'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['Surface', 'Brand', 'Color', 'Code', 'HEX', 'Finish'],
            data: surfaceRows,
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => await doc.save());
  }

  // ----- Save/Share (Firestore) -----
  Future<void> _saveToCloud() async {
    final user = FirebaseService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in to save your scene.')));
      return;
    }

    final assignmentJson = <String, dynamic>{};
    for (final s in _room.surfaces) {
      assignmentJson[s.type.name] = _assignments[s.type]?.toJson();
    }

    final doc = schema.VisualizerDoc(
      id: '', // new
      userId: user.uid,
      roomId: _roomId,
      assignments: assignmentJson,
      brightness: _brightness,
      whiteBalanceK: _whiteBalanceK,
      style: _styleTag,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final id = await FirebaseService.saveVisualizerScene(doc);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved! Share link ID: $id')));
  }

  // ----- Snapshots -----
  void _saveSnapshot() {
    if (_snapshots.length >= 4) _snapshots.removeAt(0);
    _snapshots.add(_cloneAssignments(_assignments));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Snapshot saved')));
  }

  void _applySnapshot(int index) {
    if (index < 0 || index >= _snapshots.length) return;
    _pushHistory();
    setState(() {
      _assignments
        ..clear()
        ..addAll(_cloneAssignments(_snapshots[index]));
    });
  }

  // ----- Build -----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room Visualizer'),
        actions: [
          _RoomPicker(roomId: _roomId, onChanged: (id) {
            _pushHistory();
            setState(() {
              _roomId = id;
              // ensure surfaces map has keys for the new room
              final next = { for (final s in kRoomTemplates[id]!.surfaces) s.type : _assignments[s.type] ?? const SurfaceState() };
              _assignments
                ..clear()
                ..addAll(next);
            });
          }),
          IconButton(icon: const Icon(Icons.undo), onPressed: _undoAction),
          IconButton(icon: const Icon(Icons.redo), onPressed: _redoAction),
          IconButton(icon: const Icon(Icons.camera), onPressed: _exportPng),
          IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _exportSpecPdf),
          IconButton(icon: const Icon(Icons.cloud_upload), onPressed: _saveToCloud),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Screenshot(
                controller: _shot,
                child: AspectRatio(
                  aspectRatio: _room.referenceSize.width / _room.referenceSize.height,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onTapUp: (d) => _handleTap(d.localPosition, constraints.biggest),
                        child: CustomPaint(
                          painter: _RoomPainter(
                            room: _room,
                            assignments: _assignments,
                            selected: _selectedSurface,
                            applyLighting: _applyLighting,
                          ),
                          size: Size.infinite,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          _buildControls(context),
        ],
      ),
    );
  }

  void _handleTap(Offset local, Size size) {
    // hit test polygons
    final scaleX = size.width / _room.referenceSize.width;
    final scaleY = size.height / _room.referenceSize.height;

    SurfaceType? hit;
    for (final s in _room.surfaces) {
      final path = Path()..addPolygon(s.polygon.map((p) => Offset(p.dx * scaleX, p.dy * scaleY)).toList(), true);
      if (path.contains(local)) {
        hit = s.type;
        break;
      }
    }
    setState(() => _selectedSurface = hit);
  }

  Widget _buildControls(BuildContext context) {
    final fins = Finish.values;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected surface + finish
          Row(
            children: [
              Expanded(child: Text(_selectedSurface != null
                  ? 'Selected: ${_room.surfaces.firstWhere((s) => s.type == _selectedSurface).label}'
                  : 'Tap a surface to assign a color')),
              Wrap(
                spacing: 8,
                children: fins.map((f) {
                  final isSel = _selectedSurface != null && (_assignments[_selectedSurface]?.finish == f);
                  return ChoiceChip(
                    label: Text(f.name),
                    selected: isSel,
                    onSelected: (_) => _changeFinish(f),
                  );
                }).toList(),
              ),
              const SizedBox(width: 8),
              TextButton.icon(onPressed: _saveSnapshot, icon: const Icon(Icons.bookmark_add), label: const Text('Snapshot')),
              if (_snapshots.isNotEmpty) ...{
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    shrinkWrap: true,
                    scrollDirection: Axis.horizontal,
                    itemCount: _snapshots.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (c, i) => OutlinedButton(
                      onPressed: () => _applySnapshot(i),
                      child: Text('Look ${i+1}'),
                    ),
                  ),
                ),
              },
            ],
          ),
          const SizedBox(height: 8),
          // Lighting
          Row(
            children: [
              const Text('Brightness'),
              Expanded(
                child: Slider(
                  value: _brightness,
                  min: -1, max: 1, divisions: 20,
                  onChanged: (v) => setState(() => _brightness = v),
                ),
              ),
              Text(_brightness.toStringAsFixed(2)),
              const SizedBox(width: 16),
              const Text('White Balance'),
              Expanded(
                child: Slider(
                  value: _whiteBalanceK,
                  min: 2700, max: 6500, divisions: 38,
                  onChanged: (v) => setState(() => _whiteBalanceK = v),
                ),
              ),
              Text('${_whiteBalanceK.round()}K'),
            ],
          ),
          const SizedBox(height: 8),
          // Paint search + results
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search paints by name/code/brand (e.g., "Chantilly Lace")',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: _searchPaints,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _searchPaints(_searchCtl.text),
                child: const Text('Search'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _loadRecentPaletteIntoWalls,
                child: const Text('Load Recent Palette'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: _isSearching
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (c, i) {
                    final p = _searchResults[i];
                    final cval = ColorUtils.hexToColor(p.hex);
                    final textColor = ColorUtils.isLightColor(cval) ? Colors.black : Colors.white;
                    return InkWell(
                      onTap: () => _applyPaintToSelected(p),
                      child: Container(
                        width: 160,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cval,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.brandName, style: TextStyle(color: textColor.withValues(alpha: 0.8), fontSize: 11)),
                            Text(p.name, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                            Text(p.code, style: TextStyle(color: textColor.withValues(alpha: 0.9), fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

/// Painter: fills surfaces, applies lighting, and adds finish sheen
class _RoomPainter extends CustomPainter {
  final RoomTemplate room;
  final Map<SurfaceType, SurfaceState> assignments;
  final SurfaceType? selected;
  final Color Function(Color base) applyLighting;

  _RoomPainter({required this.room, required this.assignments, required this.selected, required this.applyLighting});

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / room.referenceSize.width;
    final scaleY = size.height / room.referenceSize.height;

    // draw surfaces back-to-front
    for (final s in room.surfaces) {
      final path = Path()..addPolygon(s.polygon.map((p) => Offset(p.dx * scaleX, p.dy * scaleY)).toList(), true);
      final state = assignments[s.type];
      final baseColor = state?.paint != null
          ? ColorUtils.getPaintColor(state!.paint!)
          : Colors.grey.shade300;
      final painted = applyLighting(baseColor);

      final fill = Paint()..color = painted;
      canvas.drawPath(path, fill);

      // finish sheen overlay (subtle)
      if (state != null && (state.finish == Finish.satin || state.finish == Finish.semiGloss)) {
        final rect = path.getBounds();
        final grad = Paint()
          ..shader = ui.Gradient.linear(
            rect.topLeft,
            rect.bottomRight,
            [
              Colors.white.withValues(alpha: state.finish == Finish.semiGloss ? 0.18 : 0.10),
              Colors.transparent,
            ],
            [0.0, 1.0],
          );
        canvas.save();
        canvas.clipPath(path);
        canvas.drawRect(rect, grad);
        canvas.restore();
      }

      // selection outline
      if (selected == s.type) {
        final outline = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.blueAccent;
        canvas.drawPath(path, outline);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoomPainter old) {
    return old.assignments != assignments || old.selected != selected || old.room.id != room.id || old.applyLighting != applyLighting;
  }
}

class _RoomPicker extends StatelessWidget {
  final String roomId;
  final ValueChanged<String> onChanged;
  const _RoomPicker({required this.roomId, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: roomId,
      itemBuilder: (c) => kRoomTemplates.entries.map((e) => PopupMenuItem(value: e.key, child: Text(e.value.name))).toList(),
      onSelected: onChanged,
      child: Chip(
        label: Text(kRoomTemplates[roomId]!.name),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
    );
  }
}