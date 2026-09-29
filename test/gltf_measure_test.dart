import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maquete_ar/core/gltf_measure.dart';

/// Wraps a glTF JSON document in a GLB container. No BIN chunk: the measurer
/// only ever reads accessor bounds, which live in the JSON.
Uint8List glb(Map<String, dynamic> gltf) {
  final json = <int>[...utf8.encode(jsonEncode(gltf))];
  while (json.length % 4 != 0) {
    json.add(0x20); // pad with spaces, per the GLB spec
  }

  final out = BytesBuilder();
  final header = ByteData(12)
    ..setUint32(0, 0x46546C67, Endian.little) // 'glTF'
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, 12 + 8 + json.length, Endian.little);
  out.add(header.buffer.asUint8List());

  final chunkHeader = ByteData(8)
    ..setUint32(0, json.length, Endian.little)
    ..setUint32(4, 0x4E4F534A, Endian.little); // 'JSON'
  out.add(chunkHeader.buffer.asUint8List());
  out.add(json);

  return out.toBytes();
}

Map<String, dynamic> document({
  required List<double> min,
  required List<double> max,
  List<double>? rootMatrix,
  List<double>? rootScale,
  List<double>? childScale,
}) {
  final nodes = <Map<String, dynamic>>[];

  final root = <String, dynamic>{};
  if (rootMatrix != null) root['matrix'] = rootMatrix;
  if (rootScale != null) root['scale'] = rootScale;

  if (childScale != null) {
    root['children'] = [1];
    nodes.add(root);
    nodes.add({'mesh': 0, 'scale': childScale});
  } else {
    root['mesh'] = 0;
    nodes.add(root);
  }

  return {
    'asset': {'version': '2.0'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0]
      }
    ],
    'nodes': nodes,
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0}
          }
        ]
      }
    ],
    'accessors': [
      {'type': 'VEC3', 'componentType': 5126, 'count': 8, 'min': min, 'max': max}
    ],
  };
}

List<double> uniformMatrix(double s) => [
      s, 0, 0, 0, //
      0, s, 0, 0, //
      0, 0, s, 0, //
      0, 0, 0, 1,
    ];

Future<ModelMetrics> measureBytes(Uint8List bytes) async {
  final file = File(
    '${Directory.systemTemp.createTempSync('gltf_measure').path}/model.glb',
  )..writeAsBytesSync(bytes);
  return const GltfMeasurer().measureFile(file);
}

void main() {
  test('a model already authored in metres measures the same both ways',
      () async {
    final metrics = await measureBytes(
      glb(document(min: [0, 0, 0], max: [2.19, 0.79, 1.02])),
    );

    expect(metrics.authoredExtent, closeTo(2.19, 1e-6));
    expect(metrics.renderedExtent, closeTo(2.19, 1e-6));
    expect(metrics.realScaleFactor, closeTo(1.0, 1e-6));
  });

  test('a root scale the AR plugin discards shows up as the two extents '
      'disagreeing', () async {
    // The Duck.glb shape: 165-unit mesh, root node scaled by 0.01.
    final metrics = await measureBytes(
      glb(document(
        min: [0, 0, 0],
        max: [165.48, 164.97, 115.25],
        rootMatrix: uniformMatrix(0.01),
      )),
    );

    expect(metrics.authoredExtent, closeTo(1.6548, 1e-4));
    expect(metrics.renderedExtent, closeTo(165.48, 1e-2));
    // Placing at this scale restores the file's real 1.65 m.
    expect(metrics.realScaleFactor, closeTo(0.01, 1e-6));
  });

  test('a TRS root scale is discarded the same way a matrix one is', () async {
    final metrics = await measureBytes(
      glb(document(
        min: [0, 0, 0],
        max: [100, 50, 50],
        rootScale: [0.01, 0.01, 0.01],
      )),
    );

    expect(metrics.authoredExtent, closeTo(1.0, 1e-6));
    expect(metrics.renderedExtent, closeTo(100.0, 1e-6));
  });

  test('scale below the scene root survives, because the plugin only '
      'overwrites depth-1 nodes', () async {
    final metrics = await measureBytes(
      glb(document(
        min: [0, 0, 0],
        max: [100, 50, 50],
        childScale: [0.01, 0.01, 0.01],
      )),
    );

    expect(metrics.authoredExtent, closeTo(1.0, 1e-6));
    expect(metrics.renderedExtent, closeTo(1.0, 1e-6));
  });

  test('scaleForSize normalises any model to a requested size', () async {
    final metrics = await measureBytes(
      glb(document(
        min: [0, 0, 0],
        max: [165.48, 164.97, 115.25],
        rootMatrix: uniformMatrix(0.01),
      )),
    );

    final placed = metrics.renderedExtent * metrics.scaleForSize(0.35);
    expect(placed, closeTo(0.35, 1e-9));
  });

  test('a plain .gltf document is measured without a GLB container', () async {
    final file = File(
      '${Directory.systemTemp.createTempSync('gltf_plain').path}/model.gltf',
    )..writeAsStringSync(
        jsonEncode(document(min: [0, 0, 0], max: [3, 1, 1])),
      );

    final metrics = await const GltfMeasurer().measureFile(file);
    expect(metrics.authoredExtent, closeTo(3.0, 1e-6));
  });

  test('a file with no geometry is reported rather than silently scaled to 1',
      () async {
    final empty = glb({
      'asset': {'version': '2.0'},
      'scenes': [
        {'nodes': <int>[]}
      ],
      'nodes': <Map<String, dynamic>>[],
    });

    expect(
      () => measureBytes(empty),
      throwsA(isA<ModelMeasureException>()),
    );
  });
}
