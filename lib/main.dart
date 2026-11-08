import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_theme.dart';
import 'data/chat_database.dart';
import 'data/settings_store.dart';
import 'services/media_store.dart';
import 'state/app_state.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  final settings = await SettingsStore.open();
  final database = await ChatDatabase.open();
  final state = AppState(
    settings: settings,
    database: database,
    mediaStore: MediaStore(),
  );
  await state.init();
  runApp(FaceUpAgentsApp(state: state));
}

class FaceUpAgentsApp extends StatelessWidget {
  const FaceUpAgentsApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return MaterialApp(
          title: 'FaceUpAgents',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(
            brightness: Brightness.light,
            useInter: state.useInter,
          ),
          darkTheme: buildAppTheme(
            brightness: Brightness.dark,
            useInter: state.useInter,
          ),
          themeMode: state.themeMode,
          locale: state.language.locale,
          supportedLocales: const [Locale('en'), Locale('ru'), Locale('es')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            final dark = Theme.of(context).brightness == Brightness.dark;
            final palette = AppPalette.of(context);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value:
                  (dark
                          ? SystemUiOverlayStyle.light
                          : SystemUiOverlayStyle.dark)
                      .copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: palette.background,
                        systemNavigationBarIconBrightness: dark
                            ? Brightness.light
                            : Brightness.dark,
                      ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: AppShell(state: state),
        );
      },
    );
  }
}
