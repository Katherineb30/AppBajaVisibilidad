// ==========================================================================
// Raiz de la interfaz
// Capa MVVM: Presentacion
//
// MaterialApp: tema de alto contraste, rutas y escala tipografica minima
// garantizada. Registra los proveedores de estado de larga vida.
//
// Requisitos de la ERS que atiende:
//   - RNF-U2 alto contraste
//   - RNF-U4 tipografia escalable
// ==========================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_strings.dart';
import 'core/di/service_locator.dart';
import 'core/theme/app_theme.dart';
import 'presentation/viewmodels/home_view_model.dart';
import 'presentation/views/diagnostics_view.dart';
import 'presentation/views/home_view.dart';
import 'presentation/views/money_view.dart';
import 'presentation/views/text_view.dart';

/// Raiz del arbol de widgets.
///
/// Fija un unico tema oscuro de alto contraste (no sigue al sistema: el alto
/// contraste no es una preferencia aqui, es el requisito RNF-U2) y obliga a un
/// factor de escala tipografica minimo, de modo que la letra nunca quede por
/// debajo de lo legible aunque el usuario tenga la escala del sistema al minimo.
class VisionApp extends StatelessWidget {
  const VisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locator = ServiceLocator.instance;

    return MultiProvider(
      providers: [
        Provider.value(value: locator.tts),
        ChangeNotifierProvider(create: (_) => HomeViewModel(locator.tts)),
      ],
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.overlayStyle,
        child: MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(),
          // El tema no sigue al sistema: la aplicacion siempre usa el modo de
          // alto contraste, que es su razon de ser.
          themeMode: ThemeMode.dark,
          initialRoute: HomeView.routeName,
          routes: {
            HomeView.routeName: (_) => const HomeView(),
            TextView.routeName: (_) => const TextView(),
            MoneyView.routeName: (_) => const MoneyView(),
            DiagnosticsView.routeName: (_) => const DiagnosticsView(),
          },
          builder: (context, child) {
            // Se respeta la escala de fuente del sistema, pero se garantiza un
            // minimo generoso: nunca por debajo de 1.0 aunque el usuario la
            // haya reducido, y con tope para que no rompa el diseno.
            final scale = MediaQuery.textScalerOf(context).scale(1.0);
            final clamped = scale.clamp(1.0, 1.6).toDouble();
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(clamped),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }
}
