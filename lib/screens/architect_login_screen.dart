import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import 'architect_dashboard_screen.dart';

/// Screen 1b — architect identification.
///
/// Phase 1 keeps this profile on the device: there is no backend yet, so there
/// is nothing to authenticate against. The name typed here is what clients see
/// as the responsible architect. Phase 2 replaces this with Firebase Auth; the
/// rest of the app only reads [architectNameKey].
class ArchitectLoginScreen extends StatefulWidget {
  const ArchitectLoginScreen({super.key});

  static const architectNameKey = 'maquete_ar.architect_name';
  static const architectStudioKey = 'maquete_ar.architect_studio';

  @override
  State<ArchitectLoginScreen> createState() => _ArchitectLoginScreenState();
}

class _ArchitectLoginScreenState extends State<ArchitectLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _studioController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    _nameController.text =
        prefs.getString(ArchitectLoginScreen.architectNameKey) ?? '';
    _studioController.text =
        prefs.getString(ArchitectLoginScreen.architectStudioKey) ?? '';
    if (!mounted) return;
    setState(() => _loading = false);

    // Already identified on this device: skip straight to the projects.
    if (_nameController.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _studioController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      ArchitectLoginScreen.architectNameKey,
      _nameController.text.trim(),
    );
    await prefs.setString(
      ArchitectLoginScreen.architectStudioKey,
      _studioController.text.trim(),
    );
    _open();
  }

  void _open() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ArchitectDashboardScreen(
          architectName: _nameController.text.trim(),
          studioName: _studioController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Area do Arquiteto')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Seu nome aparece para o cliente como responsavel pelo projeto.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.inkSoft,
                      ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome do arquiteto',
                  ),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Informe seu nome'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _studioController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Escritorio (opcional)',
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Entrar'),
                ),
                const SizedBox(height: 20),
                const _PhaseNotice(
                  text:
                      'Perfil salvo apenas neste aparelho. Login com senha e '
                      'sincronizacao entre dispositivos entram na Fase 2, com Firebase.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhaseNotice extends StatelessWidget {
  const _PhaseNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.inkSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.inkSoft, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
