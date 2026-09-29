/// App-wide constants for Maquete AR.
library;

class AppInfo {
  static const String appName = 'Maquete AR';
  static const String tagline = 'Maquetes em realidade aumentada';
}

class ModelLimits {
  /// Hard ceiling for a project model file. Beyond this, mid-range phones
  /// stutter or overheat while ARCore/ARKit decodes and renders the mesh.
  static const int maxFileBytes = 30 * 1024 * 1024;

  /// Above this the upload is accepted but the architect is warned.
  static const int warnFileBytes = 20 * 1024 * 1024;

  /// Extensions the AR engine can actually render.
  /// USDZ is deliberately excluded: ARCore cannot load it and the plugin's
  /// node types only cover GLB/GLTF.
  static const List<String> allowedExtensions = ['glb', 'gltf'];
}

class AccessCode {
  static const int length = 6;
}

/// Reference models used by the "Abrir exemplo" flow (Phase 1 of the roadmap),
/// so the AR engine can be validated without any backend.
class SampleModels {
  static const String duck =
      'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/Duck/glTF-Binary/Duck.glb';
  static const String sofa =
      'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/GlamVelvetSofa/glTF-Binary/GlamVelvetSofa.glb';
  static const String chair =
      'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/SheenChair/glTF-Binary/SheenChair.glb';
}
