import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maquete_ar/app.dart';
import 'package:maquete_ar/core/theme.dart';
import 'package:maquete_ar/data/project_repository.dart';
import 'package:maquete_ar/screens/architect_dashboard_screen.dart';
import 'package:maquete_ar/screens/client_code_screen.dart';
import 'package:maquete_ar/screens/project_detail_screen.dart';
import 'package:maquete_ar/screens/project_overview_screen.dart';
import 'package:maquete_ar/screens/welcome_screen.dart';

import 'fake_project_repository.dart';

Widget host(ProjectRepository repository, Widget child) => RepositoryScope(
      repository: repository,
      child: MaterialApp(theme: buildAppTheme(), home: child),
    );

void main() {
  testWidgets('welcome screen offers both audiences', (tester) async {
    await tester.pumpWidget(
      host(FakeProjectRepository(), const WelcomeScreen()),
    );

    expect(find.text('Sou Arquiteto'), findsOneWidget);
    expect(find.text('Sou Cliente'), findsOneWidget);
  });

  testWidgets('client code screen rejects a code that matches no project',
      (tester) async {
    await tester.pumpWidget(
      host(
        FakeProjectRepository([sampleProject(accessCode: '123456')]),
        const ClientCodeScreen(),
      ),
    );

    await tester.enterText(find.byType(TextField), '999999');
    await tester.tap(find.text('Abrir projeto'));
    await tester.pumpAndSettle();

    expect(
      find.text('Codigo nao encontrado. Confira com o arquiteto.'),
      findsOneWidget,
    );
  });

  testWidgets('client code screen opens the matching project', (tester) async {
    await tester.pumpWidget(
      host(
        FakeProjectRepository([sampleProject(accessCode: '123456')]),
        const ClientCodeScreen(),
      ),
    );

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Abrir projeto'));
    await tester.pumpAndSettle();

    expect(find.byType(ProjectOverviewScreen), findsOneWidget);
    expect(find.text('Casa de Campo'), findsOneWidget);
  });

  testWidgets('overview screen starts on miniature and can switch to 1:1',
      (tester) async {
    await tester.pumpWidget(
      host(
        FakeProjectRepository(),
        ProjectOverviewScreen(project: sampleProject()),
      ),
    );

    expect(find.text('Modo Miniatura'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

    await tester.tap(find.text('Escala Real (1:1)'));
    await tester.pump();

    // Still exactly one selected option, now the other one.
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
  });

  testWidgets('overview screen disables AR when the project has no model',
      (tester) async {
    await tester.pumpWidget(
      host(
        FakeProjectRepository(),
        ProjectOverviewScreen(
          project: sampleProject(variants: const []),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Iniciar Realidade Aumentada'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('dashboard lists projects and flags the ones without a model',
      (tester) async {
    await tester.pumpWidget(
      host(
        FakeProjectRepository([
          sampleProject(id: 'a', name: 'Com modelo'),
          sampleProject(
            id: 'b',
            name: 'Sem modelo',
            accessCode: '654321',
            variants: const [],
          ),
        ]),
        const ArchitectDashboardScreen(
          architectName: 'Marllon',
          studioName: 'Estudio',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Com modelo'), findsOneWidget);
    expect(find.text('Sem modelo 3D'), findsOneWidget);
    expect(find.text('Codigo 123 456'), findsOneWidget);
  });

  testWidgets('project detail shows the access code grouped for reading aloud',
      (tester) async {
    await tester.pumpWidget(
      host(
        FakeProjectRepository(),
        ProjectDetailScreen(project: sampleProject(accessCode: '481902')),
      ),
    );

    expect(find.text('481 902'), findsOneWidget);
    expect(find.text('Compartilhar'), findsOneWidget);
  });

  testWidgets('removing the last variant disables the client preview',
      (tester) async {
    final repository = FakeProjectRepository();
    await tester.pumpWidget(
      host(
        repository,
        ProjectDetailScreen(project: sampleProject()),
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    final preview = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Ver como o cliente ve'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(preview.onPressed, isNull);
  });
}
