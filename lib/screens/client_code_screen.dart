import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import 'project_overview_screen.dart';

/// Screen 1c — the client's only gate: a six-digit code, no account.
class ClientCodeScreen extends StatefulWidget {
  const ClientCodeScreen({super.key});

  @override
  State<ClientCodeScreen> createState() => _ClientCodeScreenState();
}

class _ClientCodeScreenState extends State<ClientCodeScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.length != AccessCode.length) {
      setState(() => _error = 'O codigo tem ${AccessCode.length} digitos.');
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    final project =
        await RepositoryScope.of(context).findByAccessCode(code);

    if (!mounted) return;
    setState(() => _checking = false);

    if (project == null) {
      setState(() => _error = 'Codigo nao encontrado. Confira com o arquiteto.');
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ProjectOverviewScreen(project: project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acessar projeto')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Digite o codigo de ${AccessCode.length} digitos que o arquiteto enviou.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: AccessCode.length,
                autofillHints: const [AutofillHints.oneTimeCode],
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 14,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: TextStyle(
                    color: AppColors.line,
                    letterSpacing: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.clay),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _checking ? null : _submit,
                child: _checking
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Abrir projeto'),
              ),
              const Spacer(),
              Center(
                child: TextButton(
                  onPressed: () {
                    _controller.text = '000000';
                    _submit();
                  },
                  child: const Text('Abrir projeto de demonstracao'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
