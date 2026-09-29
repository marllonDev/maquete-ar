import '../core/gltf_measure.dart';

/// How the maquete is placed once a plane is found.
enum ArViewMode {
  /// Tabletop model: the longest side is normalised to
  /// [miniatureLongestSideMeters], whatever units the file was authored in.
  miniature,

  /// 1:1 — rendered at the size the file declares.
  realScale;

  /// A maquete this big sits on a desk and still reads from standing height.
  static const double miniatureLongestSideMeters = 0.35;

  /// Node scale to place this model at, derived from the model's own bounds.
  ///
  /// Fixed multipliers do not work here: a SketchUp export in centimetres and
  /// a Blender export in metres differ by 100x, and the AR plugin discards the
  /// scale glTF files carry on their root nodes (see [ModelMetrics]).
  double initialScaleFor(ModelMetrics metrics) => switch (this) {
        ArViewMode.miniature =>
          metrics.scaleForSize(miniatureLongestSideMeters),
        ArViewMode.realScale => metrics.realScaleFactor,
      };

  /// Pinch bounds, relative to the mode's own starting scale.
  double minScaleFor(ModelMetrics metrics) => initialScaleFor(metrics) * 0.2;
  double maxScaleFor(ModelMetrics metrics) => initialScaleFor(metrics) * 8.0;

  String get label => switch (this) {
        ArViewMode.miniature => 'Modo Miniatura',
        ArViewMode.realScale => 'Escala Real (1:1)',
      };

  String get description => switch (this) {
        ArViewMode.miniature =>
          'Ver o projeto como uma maquete sobre a mesa.',
        ArViewMode.realScale =>
          'Projetar em tamanho real no terreno. Precisa de espaco aberto.',
      };
}
