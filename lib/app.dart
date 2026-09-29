import 'package:flutter/material.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'data/project_repository.dart';
import 'screens/welcome_screen.dart';

/// Makes the [ProjectRepository] available to every screen without pulling in a
/// state-management dependency. Swapping the local repository for a Firebase
/// one in Phase 2 only changes what main() passes in here.
class RepositoryScope extends InheritedWidget {
  const RepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final ProjectRepository repository;

  static ProjectRepository of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<RepositoryScope>();
    assert(scope != null, 'No RepositoryScope found above this widget.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(RepositoryScope oldWidget) =>
      repository != oldWidget.repository;
}

class MaqueteArApp extends StatelessWidget {
  const MaqueteArApp({super.key, required this.repository});

  final ProjectRepository repository;

  @override
  Widget build(BuildContext context) {
    return RepositoryScope(
      repository: repository,
      child: MaterialApp(
        title: AppInfo.appName,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const WelcomeScreen(),
      ),
    );
  }
}
