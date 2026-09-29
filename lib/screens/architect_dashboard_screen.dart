import 'package:flutter/material.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/project.dart';
import 'project_detail_screen.dart';

/// Screen 2 — the architect's list of projects.
class ArchitectDashboardScreen extends StatefulWidget {
  const ArchitectDashboardScreen({
    super.key,
    required this.architectName,
    required this.studioName,
  });

  final String architectName;
  final String studioName;

  @override
  State<ArchitectDashboardScreen> createState() =>
      _ArchitectDashboardScreenState();
}

class _ArchitectDashboardScreenState extends State<ArchitectDashboardScreen> {
  List<Project>? _projects;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_projects == null) _reload();
  }

  Future<void> _reload() async {
    final projects = await RepositoryScope.of(context).listProjects();
    if (!mounted) return;
    setState(() => _projects = projects);
  }

  Future<void> _createProject() async {
    final result = await showModalBottomSheet<_NewProjectInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _NewProjectSheet(),
    );
    if (result == null || !mounted) return;

    final project = await RepositoryScope.of(context).createProject(
      name: result.name,
      clientName: result.clientName,
      architectName: widget.architectName,
      description: result.description,
    );
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(project: project),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus projetos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.studioName.isEmpty
                    ? widget.architectName
                    : '${widget.architectName} - ${widget.studioName}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.inkSoft),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProject,
        backgroundColor: AppColors.blueprint,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Novo projeto'),
      ),
      body: projects == null
          ? const Center(child: CircularProgressIndicator())
          : projects.isEmpty
              ? const _EmptyState()
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: projects.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      return _ProjectCard(
                        project: project,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProjectDetailScreen(project: project),
                            ),
                          );
                          await _reload();
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});

  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.line),
                ),
                child: Icon(
                  project.hasModel
                      ? Icons.view_in_ar_outlined
                      : Icons.upload_file_outlined,
                  size: 22,
                  color: project.hasModel
                      ? AppColors.blueprint
                      : AppColors.inkSoft,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      project.clientName.isEmpty
                          ? 'Sem cliente definido'
                          : project.clientName,
                      style: const TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _Tag(text: 'Codigo ${formatAccessCode(project.accessCode)}'),
                        const SizedBox(width: 6),
                        if (!project.hasModel)
                          const _Tag(
                            text: 'Sem modelo 3D',
                            color: AppColors.clay,
                          )
                        else
                          _Tag(text: formatDate(project.createdAt)),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.color = AppColors.inkSoft});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, letterSpacing: 0.2),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_outlined,
                size: 44, color: AppColors.inkSoft),
            const SizedBox(height: 16),
            Text(
              'Nenhum projeto ainda',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Crie um projeto, envie o arquivo 3D e compartilhe o codigo com o cliente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewProjectInput {
  _NewProjectInput(this.name, this.clientName, this.description);

  final String name;
  final String clientName;
  final String description;
}

class _NewProjectSheet extends StatefulWidget {
  const _NewProjectSheet();

  @override
  State<_NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends State<_NewProjectSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _client = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _client.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Novo projeto',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome do projeto',
                hintText: 'Casa de Campo',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _client,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Cliente',
                hintText: 'Joao Silva',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descricao (opcional)',
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.of(context).pop(
                  _NewProjectInput(
                    _name.text.trim(),
                    _client.text.trim(),
                    _description.text.trim(),
                  ),
                );
              },
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
  }
}
