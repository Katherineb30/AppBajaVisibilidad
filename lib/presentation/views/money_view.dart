// ==========================================================================
// Pantalla DINERO
// Capa MVVM: Presentacion
//
// Camara, caja del billete detectado y denominacion en grande.
//
// Requisitos de la ERS que atiende:
//   - RF03 billetes
//   - RF02 realidad aumentada
//   - CU03
// ==========================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/banknote_detection.dart';
import '../../data/models/recognition_status.dart';
import '../viewmodels/money_view_model.dart';
import '../widgets/analysis_indicator.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/camera_viewport.dart';
import '../widgets/overlay_painters.dart';
import '../widgets/permission_gate.dart';
import '../widgets/scan_top_bar.dart';

/// Modulo DINERO: identifica billetes colombianos y anuncia la
/// denominacion en voz alta.
class MoneyView extends StatefulWidget {
  const MoneyView({super.key});

  static const routeName = '/dinero';

  @override
  State<MoneyView> createState() => _MoneyViewState();
}

/// Estado de la pantalla DINERO.
///
/// Crea su propio MoneyViewModel (una instancia por pantalla, no compartida) y
/// observa el ciclo de vida de la aplicacion para soltar la camara y callar la
/// voz cuando la app pasa a segundo plano.
class _MoneyViewState extends State<MoneyView> with WidgetsBindingObserver {
  late final MoneyViewModel _viewModel;
  bool _started = false;

  static const Color _accent = AppColors.moneyAccent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final locator = ServiceLocator.instance;
    _viewModel = MoneyViewModel(
      cameraService: locator.newCameraService(),
      permissionService: locator.permissions,
      tts: locator.tts,
      diagnostics: locator.diagnostics,
      detectBanknote: locator.newDetectBanknoteUseCase(),
      recognizeText: locator.newRecognizeTextUseCase(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Si TalkBack esta activo el motor de voz de la aplicacion se limita a leer
    // el resultado y calla los avisos de estado: de eso ya informa el lector de
    // pantalla a traves de la region viva de la barra superior.
    _viewModel.tts.setScreenReaderActive(
      MediaQuery.accessibleNavigationOf(context),
    );
    _viewModel.initialize();
  }

  @override
  // Al salir de la aplicacion se suelta el flujo de la camara y se calla la
  // voz. Sin esto la camara seguiria analizando en segundo plano: gasto de
  // bateria (RNF-D2) y una voz que sigue hablando fuera de la app.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _viewModel.cameraService.stopStream();
      _viewModel.tts.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.dispose();
    super.dispose();
  }

  void _goHome() {
    _viewModel.tts.stop();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MoneyViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Consumer<MoneyViewModel>(
            builder: (context, vm, _) {
              if (vm.status == RecognitionStatus.permissionDenied) {
                return Column(
                  children: [
                    Expanded(
                      child: PermissionGate(
                        accent: _accent,
                        message: AppStrings.cameraPermissionBody,
                        actionLabel: AppStrings.grantPermission,
                        onAction: vm.requestPermissionAgain,
                      ),
                    ),
                    BottomActionBar(
                      accent: _accent,
                      onHome: _goHome,
                      onRepeat: vm.repeatLast,
                      repeatEnabled: false,
                    ),
                  ],
                );
              }

              final analyzing = vm.status == RecognitionStatus.analyzing;
              final note = vm.confirmed;

              return Column(
                children: [
                  ScanTopBar(
                    accent: _accent,
                    status: _statusLabel(vm),
                    autoMode: vm.autoMode,
                    torchOn: vm.torchOn,
                    onToggleTorch: vm.toggleTorch,
                    onToggleAuto: vm.toggleAutoMode,
                    overlayEnabled: vm.overlayEnabled,
                    onToggleOverlay: vm.toggleOverlay,
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CameraViewport(
                            controller: vm.cameraService.controller,
                            autoMode: vm.autoMode,
                            onTap: vm.autoMode ? null : vm.captureNow,
                            onLongPress: vm.toggleTorch,
                            overlays: [
                              if (vm.overlayEnabled)
                                CustomPaint(
                                  painter: BanknoteBoxPainter(
                                    detections:
                                        note != null ? [note] : vm.candidates,
                                    color: _accent,
                                    textDirection: Directionality.of(context),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (vm.overlayEnabled)
                          const Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: CornerFramePainter(color: _accent),
                              ),
                            ),
                          ),
                        Positioned.fill(
                          child: ScanLine(color: _accent, active: analyzing),
                        ),
                        // Mientras el modelo carga se informa de que se esta
                        // preparando; el aviso de "no disponible" solo aparece
                        // si la carga ya termino y fallo.
                        if (!vm.modelChecked)
                          const Positioned.fill(
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.all(28),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 46,
                                      height: 46,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 4,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          AppColors.moneyAccent,
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 18),
                                    Text(
                                      AppStrings.preparingModel,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.moneyAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else if (!vm.modelReady)
                          Positioned.fill(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Text(
                                  vm.modelError != null
                                      ? AppStrings.modelBroken
                                      : AppStrings.modelMissing,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onDarkMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: AnalysisIndicator(
                            accent: _accent,
                            progress: vm.progress,
                            visible: analyzing && note == null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (note != null) _NoteResult(note: note),
                  BottomActionBar(
                    accent: _accent,
                    onHome: _goHome,
                    onRepeat: vm.repeatLast,
                    repeatEnabled: note != null,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Traduce el estado interno a la frase corta de la barra superior.
  ///
  /// Es la unica fuente del aviso permanente: se ve en pantalla y TalkBack lo
  /// anuncia solo, por ser una region viva.
  String _statusLabel(MoneyViewModel vm) {
    if (!vm.modelChecked) return AppStrings.preparingModel;
    // La linterna se refleja en el indicador de estado para que TalkBack la
    // anuncie: es una region viva y nuestro aviso hablado se silencia cuando
    // hay lector de pantalla.
    if (vm.torchOn && vm.status != RecognitionStatus.success) {
      return AppStrings.torchOnStatus;
    }
    switch (vm.status) {
      case RecognitionStatus.requestingPermission:
        return 'Solicitando permiso';
      case RecognitionStatus.analyzing:
        return AppStrings.analyzing;
      case RecognitionStatus.success:
        // El rotulo sigue al tipo detectado, no al nombre del modulo.
        return vm.confirmed?.isCoin == true
            ? AppStrings.detectedCoinLabel
            : AppStrings.detectedNoteLabel;
      case RecognitionStatus.notFound:
        return AppStrings.noNoteFound;
      case RecognitionStatus.error:
        return AppStrings.cameraUnavailable;
      case RecognitionStatus.idle:
      case RecognitionStatus.searching:
      case RecognitionStatus.permissionDenied:
        return AppStrings.searchingMoney;
    }
  }
}

/// Panel de resultado del billete: la cifra ocupa el mayor tamano posible,
/// acompanada del nombre completo en palabras.
class _NoteResult extends StatelessWidget {
  const _NoteResult({required this.note});

  final BanknoteDetection note;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.moneyAccent, width: 2),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    note.isCoin
                        ? AppStrings.detectedCoinLabel
                        : AppStrings.detectedNoteLabel,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    child: Text(
                      note.displayAmount,
                      style: Theme.of(context)
                          .textTheme
                          .displayLarge
                          ?.copyWith(color: AppColors.moneyAccent),
                    ),
                  ),
                  Text(
                    note.displayName,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onDark,
                    ),
                  ),
                  // Distingue una lectura confirmada por la cifra impresa de
                  // una que solo sostiene el modelo de vision.
                  if (note.verifiedByText)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            size: 18,
                            color: AppColors.moneyAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            note.isCoin
                                ? AppStrings.verifiedOnCoin
                                : AppStrings.verifiedOnNote,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.moneyAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Sin boton "nuevo": la deteccion se reanuda sola al terminar el
            // anuncio de voz.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.chipGold,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                note.displayAmount,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.onAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
