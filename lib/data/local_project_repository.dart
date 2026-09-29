import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/project.dart';
import 'project_repository.dart';

/// Device-local storage. Project metadata goes to SharedPreferences, model
/// files to the app's documents directory (which is what the AR plugin's
/// fileSystemAppFolder node types read from).
class LocalProjectRepository implements ProjectRepository {
  LocalProjectRepository();

  static const _projectsKey = 'maquete_ar.projects.v1';
  static const _seededKey = 'maquete_ar.seeded.v1';

  final _random = Random.secure();
  late SharedPreferences _prefs;
  List<Project> _cache = const [];

  @override
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_projectsKey);
    _cache = raw == null ? const [] : Project.decodeList(raw);

    if (!(_prefs.getBool(_seededKey) ?? false)) {
      _cache = [..._cache, _demoProject()];
      await _flush();
      await _prefs.setBool(_seededKey, true);
    }
  }

  @override
  Future<List<Project>> listProjects() async =>
      List.unmodifiable(_cache.reversed);

  @override
  Future<Project?> findByAccessCode(String code) async {
    final normalized = code.trim();
    for (final p in _cache) {
      if (p.accessCode == normalized) return p;
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
      id: _newId(),
      name: name,
      clientName: clientName,
      architectName: architectName,
      accessCode: await _uniqueAccessCode(),
      description: description,
      createdAt: DateTime.now(),
      variants: const [],
    );
    _cache = [..._cache, project];
    await _flush();
    return project;
  }

  @override
  Future<void> saveProject(Project project) async {
    _cache = [
      for (final p in _cache) if (p.id == project.id) project else p,
    ];
    await _flush();
  }

  @override
  Future<void> deleteProject(String id) async {
    final target = _cache.where((p) => p.id == id).firstOrNull;
    if (target != null) {
      final dir = await getApplicationDocumentsDirectory();
      for (final v in target.variants) {
        if (v.source != ModelSource.appDocuments) continue;
        final file = File('${dir.path}/${v.uri}');
        if (file.existsSync()) {
          await file.delete();
        }
      }
    }
    _cache = _cache.where((p) => p.id != id).toList();
    await _flush();
  }

  @override
  Future<ModelVariant> importModelFile({
    required String projectId,
    required String sourcePath,
    required String label,
    required int swatchColor,
  }) async {
    final source = File(sourcePath);
    final size = await source.length();
    _assertSizeAllowed(size);

    final target = await _targetFile(projectId, sourcePath);
    await source.copy(target.path);

    return ModelVariant(
      label: label,
      swatchColor: swatchColor,
      uri: target.uri.pathSegments.last,
      source: ModelSource.appDocuments,
      fileBytes: size,
    );
  }

  @override
  Future<ModelVariant> importModelBytes({
    required String projectId,
    required Uint8List bytes,
    required String fileName,
    required String label,
    required int swatchColor,
  }) async {
    _assertSizeAllowed(bytes.length);

    final target = await _targetFile(projectId, fileName);
    await target.writeAsBytes(bytes, flush: true);

    return ModelVariant(
      label: label,
      swatchColor: swatchColor,
      uri: target.uri.pathSegments.last,
      source: ModelSource.appDocuments,
      fileBytes: bytes.length,
    );
  }

  void _assertSizeAllowed(int bytes) {
    if (bytes > ModelLimits.maxFileBytes) {
      throw ModelTooLargeException(bytes, ModelLimits.maxFileBytes);
    }
  }

  /// The plugin resolves fileSystemAppFolder nodes by bare file name, so the
  /// name has to be unique across the whole documents directory.
  Future<File> _targetFile(String projectId, String sourceName) async {
    final extension = sourceName.split('.').last.toLowerCase();
    final dir = await getApplicationDocumentsDirectory();
    return File(
      '${dir.path}/${projectId}_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
  }

  Future<void> _flush() =>
      _prefs.setString(_projectsKey, Project.encodeList(_cache));

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}${_random.nextInt(999)}';

  Future<String> _uniqueAccessCode() async {
    while (true) {
      final code = List.generate(
        AccessCode.length,
        (_) => _random.nextInt(10).toString(),
      ).join();
      if (_cache.every((p) => p.accessCode != code)) return code;
    }
  }

  /// A ready-to-open project so the AR engine can be tried on first launch,
  /// before any upload exists (Phase 1 of the roadmap).
  Project _demoProject() => Project(
        id: 'demo',
        name: 'Projeto Exemplo',
        clientName: 'Demonstracao',
        architectName: 'Maquete AR',
        accessCode: '000000',
        description:
            'Projeto de demonstracao com modelos de referencia publicos. '
            'Use para testar a realidade aumentada antes de enviar um arquivo real.',
        createdAt: DateTime.now(),
        variants: const [
          ModelVariant(
            label: 'Referencia',
            swatchColor: 0xFFB4593C,
            uri: SampleModels.duck,
            source: ModelSource.remote,
            fileBytes: 120484,
          ),
          ModelVariant(
            label: 'Estofado',
            swatchColor: 0xFF243447,
            uri: SampleModels.sofa,
            source: ModelSource.remote,
            fileBytes: 3149844,
          ),
          ModelVariant(
            label: 'Madeira',
            swatchColor: 0xFF8A6A45,
            uri: SampleModels.chair,
            source: ModelSource.remote,
            fileBytes: 4125648,
          ),
        ],
      );
}
