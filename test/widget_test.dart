import 'package:flutter_test/flutter_test.dart';

import 'package:maquete_ar/core/constants.dart';
import 'package:maquete_ar/core/gltf_measure.dart';
import 'package:maquete_ar/core/format.dart';
import 'package:maquete_ar/models/ar_view_mode.dart';
import 'package:maquete_ar/models/project.dart';

void main() {
  group('Project serialization', () {
    test('round-trips through JSON', () {
      final project = Project(
        id: 'p1',
        name: 'Casa de Campo',
        clientName: 'Joao',
        architectName: 'Marllon',
        accessCode: '123456',
        description: 'Reforma completa',
        createdAt: DateTime.parse('2026-01-15T10:00:00.000'),
        variants: const [
          ModelVariant(
            label: 'Concreto',
            swatchColor: 0xFF9B9B93,
            uri: 'p1_1.glb',
            source: ModelSource.appDocuments,
            fileBytes: 2048,
          ),
        ],
      );

      final decoded = Project.decodeList(Project.encodeList([project])).single;

      expect(decoded.id, project.id);
      expect(decoded.accessCode, '123456');
      expect(decoded.variants.single.label, 'Concreto');
      expect(decoded.variants.single.source, ModelSource.appDocuments);
      expect(decoded.createdAt, project.createdAt);
    });
  });

  group('ModelVariant.nodeType', () {
    test('maps each source and extension to the matching plugin node type', () {
      const remote = ModelVariant(
        label: 'Web',
        swatchColor: 0,
        uri: SampleModels.duck,
        source: ModelSource.remote,
      );
      const localGlb = ModelVariant(
        label: 'Local',
        swatchColor: 0,
        uri: 'a.glb',
        source: ModelSource.appDocuments,
      );
      const localGltf = ModelVariant(
        label: 'Local',
        swatchColor: 0,
        uri: 'a.gltf',
        source: ModelSource.appDocuments,
      );

      expect(remote.nodeType.name, 'webGLB');
      expect(localGlb.nodeType.name, 'fileSystemAppFolderGLB');
      expect(localGltf.nodeType.name, 'fileSystemAppFolderGLTF2');
    });
  });

  group('ArViewMode', () {
    // A 2 m model whose file renders 1:1 (no root scale thrown away).
    const honest = ModelMetrics(authoredExtent: 2.0, renderedExtent: 2.0);

    // Duck.glb: a 165-unit mesh under a root node scaled by 0.01. The AR
    // plugin overwrites that root scale, so it renders 100x too large.
    const centimetres =
        ModelMetrics(authoredExtent: 1.65, renderedExtent: 165.0);

    test('miniature normalises any model to the same tabletop size', () {
      for (final metrics in [honest, centimetres]) {
        final placed = metrics.renderedExtent *
            ArViewMode.miniature.initialScaleFor(metrics);
        expect(placed, closeTo(ArViewMode.miniatureLongestSideMeters, 1e-9));
      }
    });

    test('1:1 cancels out the scale the plugin discards', () {
      final placed = centimetres.renderedExtent *
          ArViewMode.realScale.initialScaleFor(centimetres);
      expect(placed, closeTo(1.65, 1e-9));

      final untouched =
          honest.renderedExtent * ArViewMode.realScale.initialScaleFor(honest);
      expect(untouched, closeTo(2.0, 1e-9));
    });

    test('miniature is smaller than 1:1 for a building-sized model', () {
      expect(
        ArViewMode.miniature.initialScaleFor(honest),
        lessThan(ArViewMode.realScale.initialScaleFor(honest)),
      );
    });

    test('pinch bounds bracket the initial scale', () {
      for (final mode in ArViewMode.values) {
        expect(mode.minScaleFor(honest), lessThan(mode.initialScaleFor(honest)));
        expect(
          mode.maxScaleFor(honest),
          greaterThan(mode.initialScaleFor(honest)),
        );
      }
    });
  });

  group('Formatting', () {
    test('formats byte sizes the way the upload screen shows them', () {
      expect(formatBytes(0), '--');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(30 * 1024 * 1024), '30 MB');
    });

    test('splits the access code into two readable groups', () {
      expect(formatAccessCode('123456'), '123 456');
      expect(formatAccessCode('12'), '12');
    });

    test('formats dates as dd/mm/yyyy', () {
      expect(formatDate(DateTime(2026, 3, 7)), '07/03/2026');
    });
  });
}
