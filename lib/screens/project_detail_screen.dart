import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../core/constants.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/project_repository.dart';
import '../models/project.dart';
import 'project_overview_screen.dart';

/// Screen 2b — everything the architect does with one project: read out the
/// access code, share it, and manage the 3D files.
class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.project});

  final Project project;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  late Project _project = widget.project;
  bool _importing = false;

  /// Swatch colors handed out to finish variants in the order they are added.
  static const _variantPalette = [
    0xFFEFEAE2, // parede branca
    0xFF9B9B93, // concreto
    0xFF8A6A45, // madeira
    0xFF243447, // esquadria escura
    0xFFB4593C, // terracota
  ];

  Future<void> _shareCode() async {
    final text = 'Ola${_project.clientName.isEmpty ? '' : ' ${_project.clientName}'}! '
        'O projeto "${_project.name}" ja esta disponivel em realidade aumentada '
        'no app ${AppInfo.appName}.\n\n'
        'Codigo de acesso: ${_project.accessCode}\n\n'
        'Abra o app, toque em "Sou Cliente" e digite o codigo.';
    await SharePlus.instance.share(
      ShareParams(text: text, subject: _project.name),
    );
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _project.accessCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Codigo copiado.')),
    );
  }

  Future<void> _importModel() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Selecione o modelo 3D',
      type: FileType.custom,
      allowedExtensions: ModelLimits.allowedExtensions,
    );
    if (picked == null || !mounted) return;

    final extension = (picked.extension ?? '').toLowerCase();
    if (!ModelLimits.allowedExtensions.contains(extension)) {
      _snack('Formato .$extension nao suportado. Envie .glb ou .gltf.');
      return;
    }

    final label = await _askVariantLabel();
    if (label == null || !mounted) return;

    setState(() => _importing = true);
    try {
      final repository = RepositoryScope.of(context);
      final swatchColor =
          _variantPalette[_project.variants.length % _variantPalette.length];
      final path = picked.path;
      // Android hands back a content:// URI for files outside app storage, so
      // fall back to reading the bytes when there is no readable path.
      final variant = path != null
          ? await repository.importModelFile(
              projectId: _project.id,
              sourcePath: path,
              label: label,
              swatchColor: swatchColor,
            )
          : await repository.importModelBytes(
              projectId: _project.id,
              bytes: await picked.readAsBytes(),
              fileName: picked.name,
              label: label,
              swatchColor: swatchColor,
            );
      final updated = _project.copyWith(
        variants: [..._project.variants, variant],
      );
      await repository.saveProject(updated);
      if (!mounted) return;
      setState(() {
        _project = updated;
        _importing = false;
      });
      if (variant.fileBytes > ModelLimits.warnFileBytes) {
        _snack(
          'Arquivo de ${formatBytes(variant.fileBytes)}. Acima de '
          '${formatBytes(ModelLimits.warnFileBytes)} o carregamento fica lento '
          'em celulares mais simples.',
        );
      }
    } on ModelTooLargeException catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      _snack(
        'Arquivo de ${formatBytes(e.actualBytes)}. O limite e '
        '${formatBytes(e.limitBytes)} - reduza a malha ou as texturas antes de enviar.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      _snack('Nao foi possivel importar o arquivo: $e');
    }
  }

  Future<String?> _askVariantLabel() {
    final controller = TextEditingController(
      text: _project.variants.isEmpty
          ? 'Acabamento padrao'
          : 'Opcao ${_project.variants.length + 1}',
    );
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Nome do acabamento'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Parede concreto'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
            onPressed: () {
              final value = controller.text.trim();
              Navigator.of(context).pop(value.isEmpty ? 'Acabamento' : value);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeVariant(ModelVariant variant) async {
    final repository = RepositoryScope.of(context);
    final updated = _project.copyWith(
      variants: _project.variants.where((v) => v != variant).toList(),
    );
    await repository.saveProject(updated);
    if (!mounted) return;
    setState(() => _project = updated);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_project.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _AccessCodeCard(
              code: _project.accessCode,
              onCopy: _copyCode,
              onShare: _shareCode,
            ),
            const SizedBox(height: 20),
            _SectionTitle(
              'Modelos 3D',
              trailing: '${_project.variants.length} arquivo(s)',
            ),
            const SizedBox(height: 10),
            if (_project.variants.isEmpty)
              const _UploadHint()
            else
              ..._project.variants.map(
                (v) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _VariantTile(
                    variant: v,
                    onRemove: () => _removeVariant(v),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _importing ? null : _importModel,
              icon: _importing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(
                _project.variants.isEmpty
                    ? 'Enviar arquivo 3D'
                    : 'Adicionar outro acabamento',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Formatos aceitos: .glb (recomendado) e .gltf. Limite de '
              '${formatBytes(ModelLimits.maxFileBytes)} por arquivo.\n'
              '.usdz nao e aceito: o Android nao consegue renderizar esse formato.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.inkSoft, height: 1.5),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _project.hasModel
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ProjectOverviewScreen(project: _project),
                        ),
                      )
                  : null,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Ver como o cliente ve'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessCodeCard extends StatelessWidget {
  const _AccessCodeCard({
    required this.code,
    required this.onCopy,
    required this.onShare,
  });

  final String code;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'CODIGO DE ACESSO DO CLIENTE',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                formatAccessCode(code),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 6,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copiar', maxLines: 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: onShare,
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text(
                      'Compartilhar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantTile extends StatelessWidget {
  const _VariantTile({required this.variant, required this.onRemove});

  final ModelVariant variant;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(variant.swatchColor),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    variant.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    variant.source == ModelSource.remote
                        ? 'Modelo de referencia online'
                        : '${variant.uri.split('.').last.toUpperCase()} - ${formatBytes(variant.fileBytes)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, color: AppColors.inkSoft),
              tooltip: 'Remover',
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadHint extends StatelessWidget {
  const _UploadHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, style: BorderStyle.solid),
        color: AppColors.surface,
      ),
      child: const Column(
        children: [
          Icon(Icons.view_in_ar_outlined, color: AppColors.inkSoft),
          SizedBox(height: 10),
          Text(
            'Nenhum modelo enviado ainda.',
            style: TextStyle(color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(text, style: Theme.of(context).textTheme.titleMedium),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
      ],
    );
  }
}
