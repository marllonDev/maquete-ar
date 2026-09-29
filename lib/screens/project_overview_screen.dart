import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/ar_view_mode.dart';
import '../models/project.dart';
import 'ar_screen.dart';

/// Screen 3 — what the client sees after typing the code. One decision
/// (miniature or 1:1) and one very large button.
class ProjectOverviewScreen extends StatefulWidget {
  const ProjectOverviewScreen({super.key, required this.project});

  final Project project;

  @override
  State<ProjectOverviewScreen> createState() => _ProjectOverviewScreenState();
}

class _ProjectOverviewScreenState extends State<ProjectOverviewScreen> {
  ArViewMode _mode = ArViewMode.miniature;

  void _startAr() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArScreen(project: widget.project, mode: _mode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final totalBytes =
        project.variants.fold<int>(0, (sum, v) => sum + v.fileBytes);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _CoverImage(project: project),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Projeto de ${project.architectName}',
                          style: const TextStyle(color: AppColors.inkSoft),
                        ),
                        if (project.description.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            project.description,
                            style: const TextStyle(height: 1.5),
                          ),
                        ],
                        const SizedBox(height: 24),
                        const Text(
                          'COMO VOCE QUER VER',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            color: AppColors.inkSoft,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...ArViewMode.values.map(
                          (mode) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ModeOption(
                              mode: mode,
                              selected: _mode == mode,
                              onTap: () => setState(() => _mode = mode),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (totalBytes > 0)
                          Text(
                            'Modelo: ${formatBytes(totalBytes)}. '
                            'Use Wi-Fi na primeira abertura.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.inkSoft,
                            ),
                          ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: const BoxDecoration(
                color: AppColors.paper,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                  backgroundColor: AppColors.clay,
                ),
                onPressed: project.hasModel ? _startAr : null,
                icon: const Icon(Icons.view_in_ar, size: 24),
                label: const Text(
                  'Iniciar Realidade Aumentada',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (project.coverImageUrl != null)
            Image.network(
              project.coverImageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _CoverPlaceholder(),
            )
          else
            const _CoverPlaceholder(),
          Positioned(
            top: 8,
            left: 4,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.paper,
                foregroundColor: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.blueprint,
      child: CustomPaint(painter: _GridPainter(), child: const SizedBox()),
    );
  }
}

/// A faint drafting grid, so a project without a cover photo still looks
/// deliberate rather than broken.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    const step = 26.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ArViewMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.blueprint : AppColors.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              mode == ArViewMode.miniature
                  ? Icons.table_restaurant_outlined
                  : Icons.straighten_outlined,
              color: selected ? AppColors.blueprint : AppColors.inkSoft,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    mode.description,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.inkSoft,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? AppColors.blueprint : AppColors.line,
            ),
          ],
        ),
      ),
    );
  }
}
