// ==========================================================================
// Pantalla de inicio
// Capa MVVM: Presentacion
//
// Dos destinos y nada mas. La division constante permite usar la aplicacion
// de memoria, sin mirar.
//
// Requisitos de la ERS que atiende:
//   - RNF-U1
//   - RNF-U3
//   - RF04 aviso de funcionamiento sin conexion
// ==========================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_dimens.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../viewmodels/home_view_model.dart';
import '../widgets/big_action_button.dart';
import 'diagnostics_view.dart';
import 'money_view.dart';
import 'text_view.dart';

/// Pantalla de inicio: dos destinos, nada mas.
///
/// La mitad superior lee texto y la mitad inferior identifica dinero. Esa
/// division constante permite usar la aplicacion de memoria, sin mirar.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  static const routeName = '/';

  @override
  State<HomeView> createState() => _HomeViewState();
}

/// Estado de la pantalla de inicio.
///
/// Solo guarda si ya se dio la bienvenida hablada, para no repetirla cada vez
/// que se regresa desde un modulo.
class _HomeViewState extends State<HomeView> {
  bool _announced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_announced) return;
    _announced = true;

    final screenReader = MediaQuery.accessibleNavigationOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<HomeViewModel>()
          .onScreenShown(screenReaderActive: screenReader);
    });
  }

  void _openDiagnostics(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DiagnosticsView()),
    );
  }

  Future<void> _open(Widget page) async {
    await context.read<HomeViewModel>().onModuleSelected();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (!mounted) return;
    // Al regresar, se vuelve a permitir el saludo solo si el usuario lo pide;
    // no se repite automaticamente para no resultar cansino.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.screenPadding,
            vertical: 12,
          ),
          child: Column(
            // Los hijos ocupan todo el ancho disponible: sin esto las tarjetas
            // se encogen al tamano de su texto y la pantalla queda descentrada.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Header(),
              const SizedBox(height: 18),
              Expanded(
                flex: 5,
                child: BigActionButton(
                  title: AppStrings.textModuleTitle,
                  subtitle: AppStrings.textModuleSubtitle,
                  icon: Icons.notes_rounded,
                  color: AppColors.textAccent,
                  semanticHint: 'Abre la camara para leer texto en voz alta',
                  onTap: () => _open(const TextView()),
                ),
              ),
              const SizedBox(height: AppDimens.gap),
              Expanded(
                flex: 5,
                child: BigActionButton(
                  title: AppStrings.moneyModuleTitle,
                  subtitle: AppStrings.moneyModuleSubtitle,
                  icon: Icons.payments_rounded,
                  color: AppColors.moneyAccent,
                  semanticHint:
                      'Abre la camara para identificar billetes y monedas',
                  onTap: () => _open(const MoneyView()),
                ),
              ),
              const SizedBox(height: 14),
              // RF04 / RNF-D1: se informa de que todo funciona sin conexion.
              // Una pulsacion larga sobre el pie abre el modo de diagnostico
              // (RF08 / RF10): queda a mano del tester sin estorbar al usuario.
              Semantics(
                label: '${AppStrings.appFooter}. ${AppStrings.offlineNotice}',
                hint: AppStrings.diagnosticsHint,
                onLongPress: () => _openDiagnostics(context),
                child: ExcludeSemantics(
                  child: GestureDetector(
                    onLongPress: () => _openDiagnostics(context),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.cloud_off_rounded,
                              size: 18,
                              color: AppColors.onDarkMuted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppStrings.offlineNotice,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppStrings.appFooter,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cabecera de la pantalla de inicio: nombre de la aplicacion y recordatorio
/// de que funciona sin conexion (RF04).
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: '${AppStrings.appName}. ${AppStrings.appTagline}',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.textAccent,
                borderRadius: BorderRadius.circular(18),
                boxShadow: AppTheme.glow(AppColors.textAccent, strength: 0.6),
              ),
              child: const Icon(
                Icons.accessibility_new_rounded,
                size: 40,
                color: AppColors.onAccent,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.appName,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.appTagline,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
