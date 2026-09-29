import 'dart:typed_data';

import '../models/project.dart';

/// Storage contract for projects.
///
/// Phase 1 is backed by [LocalProjectRepository] (device only). Phase 2 swaps
/// in a Firebase implementation; no screen imports a concrete repository, so
/// the UI does not change when that happens.
abstract class ProjectRepository {
  Future<void> init();

  Future<List<Project>> listProjects();

  /// Returns null when no project carries this access code.
  Future<Project?> findByAccessCode(String code);

  Future<Project> createProject({
    required String name,
    required String clientName,
    required String architectName,
    String description = '',
  });

  Future<void> saveProject(Project project);

  Future<void> deleteProject(String id);

  /// Copies [sourcePath] into app-private storage and returns the resulting
  /// [ModelVariant] pointing at it. Throws [ModelTooLargeException] when the
  /// file exceeds the supported ceiling.
  Future<ModelVariant> importModelFile({
    required String projectId,
    required String sourcePath,
    required String label,
    required int swatchColor,
  });

  /// Same as [importModelFile], for pickers that hand back bytes instead of a
  /// readable path (Android content:// URIs, for instance).
  Future<ModelVariant> importModelBytes({
    required String projectId,
    required Uint8List bytes,
    required String fileName,
    required String label,
    required int swatchColor,
  });
}

class ModelTooLargeException implements Exception {
  ModelTooLargeException(this.actualBytes, this.limitBytes);

  final int actualBytes;
  final int limitBytes;

  @override
  String toString() =>
      'Model file is ${actualBytes ~/ (1024 * 1024)} MB, limit is '
      '${limitBytes ~/ (1024 * 1024)} MB.';
}
