import 'dart:convert';

import 'package:ar_flutter_plugin_flash/datatypes/node_types.dart';

/// Where the 3D file lives. Phase 1 supports remote URLs and files the
/// architect picked on the device; Phase 2 swaps [remote] for signed Firebase
/// Storage URLs without touching the AR layer.
enum ModelSource {
  /// Absolute https URL to a .glb file.
  remote,

  /// File name (not a path) inside the app's documents directory.
  appDocuments,
}

/// One selectable finish of a project. A project always has at least one.
/// When it has more than one, the AR screen shows the swatch bar and swaps the
/// rendered model.
///
/// Note: this swaps the whole model file, not individual materials. Changing a
/// single material at runtime is not exposed by ARCore/ARKit through this
/// plugin — it would require an embedded Unity scene or custom native code.
class ModelVariant {
  const ModelVariant({
    required this.label,
    required this.swatchColor,
    required this.uri,
    required this.source,
    this.fileBytes = 0,
  });

  final String label;

  /// 0xAARRGGBB value shown in the AR swatch bar.
  final int swatchColor;

  final String uri;
  final ModelSource source;
  final int fileBytes;

  NodeType get nodeType => switch (source) {
        ModelSource.remote => NodeType.webGLB,
        ModelSource.appDocuments => uri.toLowerCase().endsWith('.gltf')
            ? NodeType.fileSystemAppFolderGLTF2
            : NodeType.fileSystemAppFolderGLB,
      };

  Map<String, dynamic> toJson() => {
        'label': label,
        'swatchColor': swatchColor,
        'uri': uri,
        'source': source.name,
        'fileBytes': fileBytes,
      };

  factory ModelVariant.fromJson(Map<String, dynamic> json) => ModelVariant(
        label: json['label'] as String,
        swatchColor: json['swatchColor'] as int,
        uri: json['uri'] as String,
        source: ModelSource.values.byName(json['source'] as String),
        fileBytes: (json['fileBytes'] as num?)?.toInt() ?? 0,
      );

  ModelVariant copyWith({
    String? label,
    int? swatchColor,
    String? uri,
    ModelSource? source,
    int? fileBytes,
  }) =>
      ModelVariant(
        label: label ?? this.label,
        swatchColor: swatchColor ?? this.swatchColor,
        uri: uri ?? this.uri,
        source: source ?? this.source,
        fileBytes: fileBytes ?? this.fileBytes,
      );
}

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.clientName,
    required this.architectName,
    required this.accessCode,
    required this.variants,
    this.description = '',
    this.coverImageUrl,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String clientName;
  final String architectName;

  /// Six-digit code the client types to open this project without an account.
  final String accessCode;

  final String description;
  final String? coverImageUrl;
  final DateTime createdAt;

  /// Never empty for a project that has a model. Empty means "upload pending".
  final List<ModelVariant> variants;

  bool get hasModel => variants.isNotEmpty;
  ModelVariant? get primaryVariant =>
      variants.isEmpty ? null : variants.first;

  Project copyWith({
    String? name,
    String? clientName,
    String? architectName,
    String? description,
    String? coverImageUrl,
    List<ModelVariant>? variants,
  }) =>
      Project(
        id: id,
        name: name ?? this.name,
        clientName: clientName ?? this.clientName,
        architectName: architectName ?? this.architectName,
        accessCode: accessCode,
        description: description ?? this.description,
        coverImageUrl: coverImageUrl ?? this.coverImageUrl,
        createdAt: createdAt,
        variants: variants ?? this.variants,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'clientName': clientName,
        'architectName': architectName,
        'accessCode': accessCode,
        'description': description,
        'coverImageUrl': coverImageUrl,
        'createdAt': createdAt.toIso8601String(),
        'variants': variants.map((v) => v.toJson()).toList(),
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        clientName: json['clientName'] as String,
        architectName: json['architectName'] as String,
        accessCode: json['accessCode'] as String,
        description: json['description'] as String? ?? '',
        coverImageUrl: json['coverImageUrl'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        variants: (json['variants'] as List<dynamic>)
            .map((v) => ModelVariant.fromJson(v as Map<String, dynamic>))
            .toList(),
      );

  static String encodeList(List<Project> projects) =>
      jsonEncode(projects.map((p) => p.toJson()).toList());

  static List<Project> decodeList(String raw) =>
      (jsonDecode(raw) as List<dynamic>)
          .map((e) => Project.fromJson(e as Map<String, dynamic>))
          .toList();
}
