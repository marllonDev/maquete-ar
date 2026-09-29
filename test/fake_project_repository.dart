import 'dart:typed_data';

import 'package:maquete_ar/data/project_repository.dart';
import 'package:maquete_ar/models/project.dart';

/// In-memory repository so widget tests can exercise screens without touching
/// SharedPreferences or the file system.
class FakeProjectRepository implements ProjectRepository {
  FakeProjectRepository([List<Project>? seed]) : _projects = [...?seed];

  final List<Project> _projects;
  int _nextCode = 100000;

  @override
  Future<void> init() async {}

  @override
  Future<List<Project>> listProjects() async => List.of(_projects);

  @override
  Future<Project?> findByAccessCode(String code) async {
    for (final p in _projects) {
      if (p.accessCode == code) return p;
    }
    return null;
  }

  @override
  Future<Project> createProject({
    required String name,
    required String clientName,
    required String architectName,
    String description = '',
  }) async {
    final project = Project(
      id: 'p${_projects.length}',
      name: name,
      clientName: clientName,
      architectName: architectName,
      accessCode: '${_nextCode++}',
      description: description,
      createdAt: DateTime(2026, 1, 1),
      variants: const [],
    );
    _projects.add(project);
    return project;
  }

  @override
  Future<void> saveProject(Project project) async {
    final index = _projects.indexWhere((p) => p.id == project.id);
    if (index >= 0) _projects[index] = project;
  }

  @override
  Future<void> deleteProject(String id) async =>
      _projects.removeWhere((p) => p.id == id);

  @override
  Future<ModelVariant> importModelFile({
    required String projectId,
    required String sourcePath,
    required String label,
    required int swatchColor,
  }) async =>
      ModelVariant(
        label: label,
        swatchColor: swatchColor,
        uri: 'imported.glb',
        source: ModelSource.appDocuments,
        fileBytes: 1024,
      );

  @override
  Future<ModelVariant> importModelBytes({
    required String projectId,
    required Uint8List bytes,
    required String fileName,
    required String label,
    required int swatchColor,
  }) async =>
      ModelVariant(
        label: label,
        swatchColor: swatchColor,
        uri: fileName,
        source: ModelSource.appDocuments,
        fileBytes: bytes.length,
      );
}

Project sampleProject({
  String id = 'p1',
  String name = 'Casa de Campo',
  String accessCode = '123456',
  List<ModelVariant> variants = const [
    ModelVariant(
      label: 'Concreto',
      swatchColor: 0xFF9B9B93,
      uri: 'casa.glb',
      source: ModelSource.appDocuments,
      fileBytes: 4 * 1024 * 1024,
    ),
  ],
}) =>
    Project(
      id: id,
      name: name,
      clientName: 'Joao Silva',
      architectName: 'Marllon',
      accessCode: accessCode,
      description: 'Residencia unifamiliar em terreno de esquina.',
      createdAt: DateTime(2026, 3, 7),
      variants: variants,
    );
