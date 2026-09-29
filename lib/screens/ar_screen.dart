import 'dart:io';
import 'dart:typed_data';

import 'package:ar_flutter_plugin_flash/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_flash/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_flash/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_flash/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_flash/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_flash/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_flash/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_flash/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_flash/models/ar_node.dart';
import 'package:ar_flutter_plugin_flash/widgets/ar_view.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../core/gltf_measure.dart';
import '../core/theme.dart';
import '../models/ar_view_mode.dart';
import '../models/project.dart';

/// Screen 4 — the camera.
///
/// Responsibilities, in the order the user meets them:
///  1. detect a horizontal plane (ARCore/ARKit do this; we only coach the user);
///  2. place the maquete on an [ARPlaneAnchor] so it stays put when the camera
///     moves — the anchor, not the node, is what stops the model from sliding;
///  3. let the user pinch to scale and twist to rotate;
///  4. let the user reset, swap the finish, and save a photo.
class ArScreen extends StatefulWidget {
  const ArScreen({super.key, required this.project, required this.mode});

  final Project project;
  final ArViewMode mode;

  @override
  State<ArScreen> createState() => _ArScreenState();
}

class _ArScreenState extends State<ArScreen> {
  ARSessionManager? _sessionManager;
  ARObjectManager? _objectManager;
  ARAnchorManager? _anchorManager;

  ARPlaneAnchor? _anchor;
  ARNode? _node;

  late ModelVariant _variant = widget.project.variants.first;

  int _detectedPlanes = 0;
  bool _busy = false;
  String? _toast;

  /// Asked for before [ARView] is built. The plugin renders its own unstyled
  /// prompt on top of the camera when permission is missing, which collides
  /// with this screen's overlay — so the gate lives here instead.
  PermissionStatus? _cameraPermission;

  /// Live transform of the placed node, kept in Dart so pinch/twist can be
  /// applied on top of the previous value instead of fighting it.
  double _scale = 1.0;
  double _yaw = 0.0;
  double _scaleAtGestureStart = 1.0;
  double _yawAtGestureStart = 0.0;

  /// Bounds per variant uri. Without these the model is placed at whatever
  /// size its file happens to declare, which for a centimetre-authored export
  /// means a maquete 100x too big to see.
  final Map<String, ModelMetrics> _metrics = {};
  final GltfMeasurer _measurer = const GltfMeasurer();
  bool _measuring = false;
  String? _measureError;

  bool get _isPlaced => _node != null;
  ModelMetrics? get _currentMetrics => _metrics[_variant.uri];

  /// How much the user has pinched away from the mode's own starting size.
  /// Kept across a finish swap so a different file does not reset the zoom.
  double _zoomRatio = 1.0;

  @override
  void initState() {
    super.initState();
    _requestCamera();
    _measure(_variant);
  }

  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _cameraPermission = status);
  }

  /// Reads the model's bounding box so the placement scale can be derived from
  /// it. Only the glTF JSON header is fetched, never the vertex data.
  Future<void> _measure(ModelVariant variant) async {
    if (_metrics.containsKey(variant.uri)) {
      _applyBaseScale();
      return;
    }

    setState(() {
      _measuring = true;
      _measureError = null;
    });

    try {
      final metrics = switch (variant.source) {
        ModelSource.remote =>
          await _measurer.measureUrl(Uri.parse(variant.uri)),
        ModelSource.appDocuments =>
          await _measurer.measureFile(File(await _documentsPath(variant.uri))),
      };
      if (!mounted) return;
      setState(() {
        _metrics[variant.uri] = metrics;
        _measuring = false;
      });
      _applyBaseScale();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _measuring = false;
        _measureError = e is ModelMeasureException ? e.message : '$e';
      });
    }
  }

  Future<String> _documentsPath(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$fileName';
  }

  /// Recomputes the node scale from the current model's bounds, preserving
  /// whatever zoom the user had pinched to.
  void _applyBaseScale() {
    final metrics = _currentMetrics;
    if (metrics == null) return;
    final base = widget.mode.initialScaleFor(metrics);
    setState(() => _scale = base * _zoomRatio);
    _applyTransform();
  }

  @override
  void dispose() {
    _sessionManager?.dispose();
    super.dispose();
  }

  void _onArViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) {
    _sessionManager = sessionManager;
    _objectManager = objectManager;
    _anchorManager = anchorManager;

    sessionManager.onInitialize(
      showAnimatedGuide: true,
      autoHideCoachingOverlay: true,
      showFeaturePoints: false,
      showPlanes: true,
      showWorldOrigin: false,
      handleTaps: true,
      // Single-finger drag moves the model along the plane, natively.
      handlePans: true,
      // Rotation is handled in Flutter together with pinch, so the two gestures
      // cannot fight each other over the same two fingers.
      handleRotation: false,
    );
    // Neutral scale factors: the node's own scale is the single source of
    // truth, so iOS and Android place the model at the same size.
    objectManager.onInitialize(iosScaleFactor: 1.0, androidScaleFactor: 1.0);

    sessionManager.onPlaneOrPointTap = _onPlaneOrPointTap;
    sessionManager.onPlanesUpdated = (count) {
      if (!mounted || count == _detectedPlanes) return;
      setState(() => _detectedPlanes = count);
    };
  }

  Future<void> _onPlaneOrPointTap(List<ARHitTestResult> hits) async {
    // Placing before the bounds are known would use an arbitrary scale.
    if (_isPlaced || _busy || _currentMetrics == null) return;

    final hit = hits
        .where((h) => h.type == ARHitTestResultType.plane)
        .firstOrNull;
    if (hit == null) return;

    setState(() => _busy = true);
    await _placeAt(hit.worldTransform);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _placeAt(vm.Matrix4 worldTransform) async {
    final anchor = ARPlaneAnchor(transformation: worldTransform);
    final anchorAdded = await _anchorManager?.addAnchor(anchor) ?? false;
    if (!anchorAdded) {
      _showToast('Nao consegui fixar neste ponto. Tente outra area do chao.');
      return;
    }

    final node = _buildNode();
    final nodeAdded =
        await _objectManager?.addNode(node, planeAnchor: anchor) ?? false;
    if (!nodeAdded) {
      _anchorManager?.removeAnchor(anchor);
      _showToast('Nao consegui carregar o modelo 3D. Verifique a conexao.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _anchor = anchor;
      _node = node;
    });
  }

  ARNode _buildNode() => ARNode(
        type: _variant.nodeType,
        uri: _variant.uri,
        scale: vm.Vector3.all(_scale),
        position: vm.Vector3.zero(),
        rotation: vm.Vector4(0, 1, 0, _yaw),
      );

  /// Rebuilds the node transform from the Dart-side scale and yaw, keeping the
  /// translation the native pan gesture may have applied.
  void _applyTransform() {
    final node = _node;
    if (node == null) return;
    final translation = node.transform.getTranslation();
    node.transform = vm.Matrix4.compose(
      translation,
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _yaw),
      vm.Vector3.all(_scale),
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _scaleAtGestureStart = _scale;
    _yawAtGestureStart = _yaw;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // One finger is a pan, which the native layer already handles.
    if (details.pointerCount < 2 || !_isPlaced) return;
    final metrics = _currentMetrics;
    if (metrics == null) return;

    final base = widget.mode.initialScaleFor(metrics);
    _scale = (_scaleAtGestureStart * details.scale).clamp(
      widget.mode.minScaleFor(metrics),
      widget.mode.maxScaleFor(metrics),
    );
    _zoomRatio = base <= 0 ? 1.0 : _scale / base;
    _yaw = _yawAtGestureStart + details.rotation;
    _applyTransform();
    setState(() {});
  }

  Future<void> _reset() async {
    final node = _node;
    final anchor = _anchor;
    if (node != null) _objectManager?.removeNode(node);
    if (anchor != null) _anchorManager?.removeAnchor(anchor);
    if (!mounted) return;
    setState(() {
      _node = null;
      _anchor = null;
      _yaw = 0;
      _zoomRatio = 1.0;
    });
    _applyBaseScale();
  }

  Future<void> _selectVariant(ModelVariant variant) async {
    if (variant == _variant) return;
    setState(() => _variant = variant);

    // Each file has its own units, so the placement scale is recomputed here.
    await _measure(variant);
    if (!mounted || _currentMetrics == null) return;

    // Not placed yet: the new file will simply be used on the next tap.
    final anchor = _anchor;
    final node = _node;
    if (anchor == null || node == null) return;

    setState(() => _busy = true);
    _objectManager?.removeNode(node);
    final replacement = _buildNode();
    final added =
        await _objectManager?.addNode(replacement, planeAnchor: anchor) ?? false;
    if (!mounted) return;
    setState(() {
      _node = added ? replacement : null;
      _busy = false;
    });
    if (!added) {
      _showToast('Nao consegui carregar este acabamento.');
    }
  }

  Future<void> _takeSnapshot() async {
    final session = _sessionManager;
    if (session == null || _busy) return;

    setState(() => _busy = true);
    // Detected-plane overlays would end up in the photo, so hide them first.
    await session.updateVisibilityOptions(showPlanes: false);
    try {
      final image = await session.snapshot();
      final bytes = (image as MemoryImage).bytes;
      await _saveToGallery(bytes);
    } catch (e) {
      _showToast('Nao consegui capturar a tela: $e');
    } finally {
      await session.updateVisibilityOptions(showPlanes: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveToGallery(Uint8List bytes) async {
    if (!await Gal.hasAccess(toAlbum: true)) {
      final granted = await Gal.requestAccess(toAlbum: true);
      if (!granted) {
        _showToast('Permissao de fotos negada. A imagem nao foi salva.');
        return;
      }
    }
    await Gal.putImageBytes(
      bytes,
      album: 'Maquete AR',
      name: '${widget.project.name}_${DateTime.now().millisecondsSinceEpoch}',
    );
    _showToast('Foto salva na galeria.');
  }

  void _showToast(String message) {
    if (!mounted) return;
    setState(() => _toast = message);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _toast == message) setState(() => _toast = null);
    });
  }

  String get _coachText {
    if (_measureError != null) {
      return 'Nao consegui ler o modelo 3D deste acabamento.\n$_measureError';
    }
    if (_measuring) return 'Preparando a maquete...';
    if (_busy && !_isPlaced) return 'Carregando a maquete...';
    if (_isPlaced) return '';
    if (_detectedPlanes == 0) {
      return 'Mova o celular devagar para detectar o chao...';
    }
    return 'Toque na superficie destacada para posicionar a maquete.';
  }

  @override
  Widget build(BuildContext context) {
    final variants = widget.project.variants;

    final permission = _cameraPermission;
    if (permission == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    if (permission != PermissionStatus.granted &&
        permission != PermissionStatus.limited) {
      return _CameraDeniedScreen(
        restricted: permission == PermissionStatus.restricted,
        onRetry: permission == PermissionStatus.permanentlyDenied
            ? openAppSettings
            : _requestCamera,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ARView(
            onARViewCreated: _onArViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontal,
          ),

          // The camera feed can be any brightness, so the white overlay text
          // gets its own scrims instead of relying on the scene behind it.
          const _Scrim(alignment: Alignment.topCenter, height: 200),
          const _Scrim(alignment: Alignment.bottomCenter, height: 260),

          // Pinch to scale / twist to rotate. Only active once the maquete is
          // placed, so the placement tap still reaches the native AR view.
          if (_isPlaced)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
              ),
            ),

          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  title: widget.project.name,
                  subtitle: widget.mode.label,
                  onClose: () => Navigator.of(context).maybePop(),
                  onReset: _isPlaced ? _reset : null,
                ),
                const SizedBox(height: 10),
                if (_coachText.isNotEmpty) _CoachChip(text: _coachText),
                if (_isPlaced && _currentMetrics != null)
                  _ScaleReadout(
                    metrics: _currentMetrics!,
                    scale: _scale,
                  ),
                const Spacer(),
                if (_toast != null) _Toast(text: _toast!),
                if (variants.length > 1)
                  _FinishBar(
                    variants: variants,
                    selected: _variant,
                    onSelect: _busy ? null : _selectVariant,
                  ),
                _BottomBar(
                  canCapture: _isPlaced && !_busy,
                  busy: _busy,
                  onCapture: _takeSnapshot,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.onReset,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _GlassButton(icon: Icons.close, onPressed: onClose),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                  ),
                ),
              ],
            ),
          ),
          _GlassButton(
            icon: Icons.refresh,
            onPressed: onReset,
            label: 'Reposicionar',
          ),
        ],
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.onPressed,
    this.label,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: Colors.black.withValues(alpha: enabled ? 0.45 : 0.2),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label == null ? 11 : 14,
            vertical: 11,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: enabled ? Colors.white : Colors.white38,
              ),
              if (label != null) ...[
                const SizedBox(width: 7),
                Text(
                  label!,
                  style: TextStyle(
                    color: enabled ? Colors.white : Colors.white38,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachChip extends StatelessWidget {
  const _CoachChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

/// Reports the maquete's real-world size and how it compares to the project's
/// true dimensions — an architect cares about "1:50", not "80%".
class _ScaleReadout extends StatelessWidget {
  const _ScaleReadout({required this.metrics, required this.scale});

  final ModelMetrics metrics;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final sizeMeters = metrics.renderedExtent * scale;
    final ratio = metrics.authoredExtent <= 0
        ? null
        : metrics.authoredExtent / sizeMeters;

    final size = sizeMeters >= 1
        ? '${sizeMeters.toStringAsFixed(2).replaceAll('.', ',')} m'
        : '${(sizeMeters * 100).round()} cm';
    final ratioLabel = ratio == null
        ? ''
        : ratio < 1.05 && ratio > 0.95
            ? '  -  escala 1:1'
            : '  -  escala 1:${ratio.round()}';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$size$ratioLabel',
          style: const TextStyle(color: Colors.white70, fontSize: 11.5),
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }
}

class _FinishBar extends StatelessWidget {
  const _FinishBar({
    required this.variants,
    required this.selected,
    required this.onSelect,
  });

  final List<ModelVariant> variants;
  final ModelVariant selected;
  final ValueChanged<ModelVariant>? onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: variants.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final variant = variants[index];
          final isSelected = variant == selected;
          return GestureDetector(
            onTap: onSelect == null ? null : () => onSelect!(variant),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(variant.swatchColor),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.white30,
                      width: isSelected ? 3 : 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 68,
                  child: Text(
                    variant.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.canCapture,
    required this.busy,
    required this.onCapture,
  });

  final bool canCapture;
  final bool busy;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: canCapture ? onCapture : null,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: canCapture ? Colors.white : Colors.white30,
                  width: 3,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: canCapture
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Vertical black-to-transparent wash that keeps the overlay readable over a
/// bright camera feed.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.alignment, required this.height});

  final Alignment alignment;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fromTop = alignment == Alignment.topCenter;
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the AR view when the camera is unavailable, so the user
/// gets an explanation rather than a black screen.
class _CameraDeniedScreen extends StatelessWidget {
  const _CameraDeniedScreen({
    required this.restricted,
    required this.onRetry,
  });

  final bool restricted;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Realidade aumentada')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.no_photography_outlined,
                size: 44, color: AppColors.inkSoft),
            const SizedBox(height: 20),
            Text(
              restricted
                  ? 'Camera bloqueada pelo aparelho'
                  : 'Precisamos da camera',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              restricted
                  ? 'O acesso a camera esta bloqueado nas restricoes do sistema. '
                      'Peca a quem administra o aparelho para liberar.'
                  : 'A maquete e desenhada sobre a imagem da camera. Sem esse '
                      'acesso nao ha como mostrar o projeto no ambiente real.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkSoft, height: 1.5),
            ),
            const SizedBox(height: 28),
            if (!restricted)
              FilledButton(
                onPressed: onRetry,
                child: const Text('Permitir camera'),
              ),
            const Spacer(),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}
