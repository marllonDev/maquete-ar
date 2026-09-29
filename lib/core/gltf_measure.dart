import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:vector_math/vector_math_64.dart';

/// How big a model is, measured two ways.
///
/// The two differ because `ar_flutter_plugin_flash` overwrites the scale of
/// every node directly under the glTF scene root
/// (`ArModelBuilder.swift`: `child.scale = SCNVector3(iosModelScaleFactor...)`),
/// which throws away any scale the file carries on those nodes. A file like
/// Khronos' `Duck.glb` — a 165-unit mesh under a root node scaled by 0.01 —
/// therefore renders 100x too large.
///
/// Knowing both numbers lets the AR screen cancel that out instead of trusting
/// the file's units blindly.
class ModelMetrics {
  const ModelMetrics({required this.authoredExtent, required this.renderedExtent});

  /// Longest bounding-box side with every node transform applied, i.e. the
  /// size the file actually claims. glTF declares meters.
  final double authoredExtent;

  /// Longest bounding-box side as the plugin renders it at node scale 1.
  final double renderedExtent;

  /// Node scale that makes the model appear at its authored real-world size.
  double get realScaleFactor =>
      renderedExtent <= 0 ? 1.0 : authoredExtent / renderedExtent;

  /// Node scale that makes the model's longest side measure [meters].
  double scaleForSize(double meters) =>
      renderedExtent <= 0 ? 1.0 : meters / renderedExtent;

  @override
  String toString() =>
      'ModelMetrics(authored: ${authoredExtent.toStringAsFixed(3)}m, '
      'rendered: ${renderedExtent.toStringAsFixed(3)})';
}

class ModelMeasureException implements Exception {
  ModelMeasureException(this.message);

  final String message;

  @override
  String toString() => 'ModelMeasureException: $message';
}

/// Reads the bounding box of a `.glb` / `.gltf` model.
///
/// Only the JSON part of the file is needed: vertex bounds live in the
/// accessors' `min` / `max`, so no vertex buffer is ever downloaded or parsed.
class GltfMeasurer {
  const GltfMeasurer();

  /// Enough for the JSON chunk of any realistic model; bigger headers fall
  /// back to a full download.
  static const int _headerProbeBytes = 512 * 1024;

  Future<ModelMetrics> measureFile(File file) async {
    final length = await file.length();
    final handle = await file.open();
    try {
      final head = await handle.read(
        length < _headerProbeBytes ? length : _headerProbeBytes,
      );
      final json = _extractJson(head, () async {
        await handle.setPosition(0);
        return handle.read(length);
      });
      return _measure(await json);
    } finally {
      await handle.close();
    }
  }

  Future<ModelMetrics> measureUrl(Uri url, {http.Client? client}) async {
    final ownedClient = client == null;
    final http$ = client ?? http.Client();
    try {
      final ranged = await http$.get(
        url,
        headers: {'Range': 'bytes=0-${_headerProbeBytes - 1}'},
      );
      if (ranged.statusCode != 200 && ranged.statusCode != 206) {
        throw ModelMeasureException(
          'HTTP ${ranged.statusCode} ao ler $url',
        );
      }
      final json = await _extractJson(ranged.bodyBytes, () async {
        final full = await http$.get(url);
        if (full.statusCode != 200) {
          throw ModelMeasureException('HTTP ${full.statusCode} ao ler $url');
        }
        return full.bodyBytes;
      });
      return _measure(json);
    } finally {
      if (ownedClient) http$.close();
    }
  }

  /// Returns the glTF JSON, either straight from a `.gltf` document or out of
  /// a GLB container's first chunk. [readAll] is only called when the probe
  /// did not cover the whole JSON chunk.
  Future<Map<String, dynamic>> _extractJson(
    Uint8List head,
    Future<Uint8List> Function() readAll,
  ) async {
    if (head.length < 12) {
      throw ModelMeasureException('Arquivo muito curto para ser glTF.');
    }

    final isGlb = head[0] == 0x67 && // g
        head[1] == 0x6C && // l
        head[2] == 0x54 && // T
        head[3] == 0x46; // F

    if (!isGlb) {
      // A .gltf document is plain JSON, and a truncated probe would not parse.
      final all = head.length < _headerProbeBytes ? head : await readAll();
      return jsonDecode(utf8.decode(all)) as Map<String, dynamic>;
    }

    final view = ByteData.sublistView(head);
    final chunkLength = view.getUint32(12, Endian.little);
    final chunkType = view.getUint32(16, Endian.little);
    if (chunkType != 0x4E4F534A) {
      throw ModelMeasureException('Primeiro chunk do GLB nao e JSON.');
    }

    final bytes = head.length >= 20 + chunkLength ? head : await readAll();
    return jsonDecode(
      utf8.decode(Uint8List.sublistView(bytes, 20, 20 + chunkLength)),
    ) as Map<String, dynamic>;
  }

  ModelMetrics _measure(Map<String, dynamic> gltf) {
    final authored = _Bounds();
    final rendered = _Bounds();

    final nodes = (gltf['nodes'] as List<dynamic>? ?? const []);
    final scenes = (gltf['scenes'] as List<dynamic>? ?? const []);
    final sceneIndex = (gltf['scene'] as num?)?.toInt() ?? 0;

    final roots = scenes.isEmpty
        ? List<int>.generate(nodes.length, (i) => i)
        : ((scenes[sceneIndex.clamp(0, scenes.length - 1)]
                    as Map<String, dynamic>)['nodes'] as List<dynamic>? ??
                const [])
            .map((e) => (e as num).toInt())
            .toList();

    for (final root in roots) {
      _walk(gltf, root, Matrix4.identity(), authored, depth: 0,
          stripRootScale: false);
      _walk(gltf, root, Matrix4.identity(), rendered, depth: 0,
          stripRootScale: true);
    }

    if (authored.isEmpty || rendered.isEmpty) {
      throw ModelMeasureException('Modelo sem geometria mensuravel.');
    }
    return ModelMetrics(
      authoredExtent: authored.longestSide,
      renderedExtent: rendered.longestSide,
    );
  }

  void _walk(
    Map<String, dynamic> gltf,
    int nodeIndex,
    Matrix4 parent,
    _Bounds bounds, {
    required int depth,
    required bool stripRootScale,
  }) {
    final nodes = gltf['nodes'] as List<dynamic>;
    if (nodeIndex < 0 || nodeIndex >= nodes.length) return;
    final node = nodes[nodeIndex] as Map<String, dynamic>;

    var local = _localMatrix(node);
    if (stripRootScale && depth == 0) {
      local = _withoutScale(local);
    }
    final world = parent * local;

    final meshIndex = (node['mesh'] as num?)?.toInt();
    if (meshIndex != null) {
      _accumulateMesh(gltf, meshIndex, world, bounds);
    }

    for (final child in (node['children'] as List<dynamic>? ?? const [])) {
      _walk(gltf, (child as num).toInt(), world, bounds,
          depth: depth + 1, stripRootScale: stripRootScale);
    }
  }

  Matrix4 _localMatrix(Map<String, dynamic> node) {
    final matrix = node['matrix'] as List<dynamic>?;
    if (matrix != null && matrix.length == 16) {
      return Matrix4.fromList(
        matrix.map((e) => (e as num).toDouble()).toList(),
      );
    }

    final t = node['translation'] as List<dynamic>?;
    final r = node['rotation'] as List<dynamic>?;
    final s = node['scale'] as List<dynamic>?;

    return Matrix4.compose(
      t == null
          ? Vector3.zero()
          : Vector3(
              (t[0] as num).toDouble(),
              (t[1] as num).toDouble(),
              (t[2] as num).toDouble(),
            ),
      r == null
          ? Quaternion.identity()
          : Quaternion(
              (r[0] as num).toDouble(),
              (r[1] as num).toDouble(),
              (r[2] as num).toDouble(),
              (r[3] as num).toDouble(),
            ),
      s == null
          ? Vector3.all(1)
          : Vector3(
              (s[0] as num).toDouble(),
              (s[1] as num).toDouble(),
              (s[2] as num).toDouble(),
            ),
    );
  }

  /// Keeps rotation and translation, forces scale to 1 — what SceneKit ends up
  /// with when the plugin assigns `node.scale` directly.
  Matrix4 _withoutScale(Matrix4 matrix) {
    final translation = Vector3.zero();
    final rotation = Quaternion.identity();
    final scale = Vector3.zero();
    matrix.decompose(translation, rotation, scale);
    return Matrix4.compose(translation, rotation, Vector3.all(1));
  }

  void _accumulateMesh(
    Map<String, dynamic> gltf,
    int meshIndex,
    Matrix4 world,
    _Bounds bounds,
  ) {
    final meshes = gltf['meshes'] as List<dynamic>? ?? const [];
    if (meshIndex < 0 || meshIndex >= meshes.length) return;
    final accessors = gltf['accessors'] as List<dynamic>? ?? const [];

    final primitives = (meshes[meshIndex] as Map<String, dynamic>)['primitives']
            as List<dynamic>? ??
        const [];

    for (final primitive in primitives) {
      final attributes =
          (primitive as Map<String, dynamic>)['attributes'] as Map<String, dynamic>?;
      final positionIndex = (attributes?['POSITION'] as num?)?.toInt();
      if (positionIndex == null ||
          positionIndex < 0 ||
          positionIndex >= accessors.length) {
        continue;
      }

      final accessor = accessors[positionIndex] as Map<String, dynamic>;
      final min = accessor['min'] as List<dynamic>?;
      final max = accessor['max'] as List<dynamic>?;
      if (min == null || max == null || min.length < 3 || max.length < 3) {
        continue;
      }

      final lo = [
        (min[0] as num).toDouble(),
        (min[1] as num).toDouble(),
        (min[2] as num).toDouble(),
      ];
      final hi = [
        (max[0] as num).toDouble(),
        (max[1] as num).toDouble(),
        (max[2] as num).toDouble(),
      ];

      // A rotated box is not axis-aligned any more, so every corner counts.
      for (var corner = 0; corner < 8; corner++) {
        final point = Vector3(
          (corner & 1) == 0 ? lo[0] : hi[0],
          (corner & 2) == 0 ? lo[1] : hi[1],
          (corner & 4) == 0 ? lo[2] : hi[2],
        );
        bounds.add(world.transformed3(point));
      }
    }
  }
}

class _Bounds {
  Vector3? _min;
  Vector3? _max;

  bool get isEmpty => _min == null;

  void add(Vector3 point) {
    final min = _min;
    final max = _max;
    if (min == null || max == null) {
      _min = point.clone();
      _max = point.clone();
      return;
    }
    Vector3.min(min, point, min);
    Vector3.max(max, point, max);
  }

  double get longestSide {
    final min = _min;
    final max = _max;
    if (min == null || max == null) return 0;
    final size = max - min;
    return [size.x, size.y, size.z].reduce((a, b) => a > b ? a : b);
  }
}
