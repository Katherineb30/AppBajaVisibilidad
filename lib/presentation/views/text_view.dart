// ==========================================================================
// Pantalla TEXTO
// Capa MVVM: Presentacion
//
// Camara, resaltado de las lineas detectadas y panel de resultado.
//
// Requisitos de la ERS que atiende:
//   - RF01 OCR
//   - RF02 realidad aumentada
//   - CU01
// ==========================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/recognition_status.dart';
import '../viewmodels/text_view_model.dart';
import '../widgets/analysis_indicator.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/camera_viewport.dart';
import '../widgets/overlay_painters.dart';
import '../widgets/permission_gate.dart';
import '../widgets/result_panel.dart';
import '../widgets/scan_top_bar.dart';

/// Modulo TEXTO: lee en voz alta el texto impreso que enfoca la camara.
class TextView extends StatefulWidget {
  const TextView({super.key});

  static const routeName = '/texto';

  @override
  State<TextView> createState() => _TextViewState();
}

/// Estado de la pantalla TEXTO.
///
/// Simetrico a la pantalla de dinero: ViewModel propio, liberacion de camara y
/// voz al pasar a segundo plano, y aviso al motor de voz de si hay lector de
/// pantalla activo.
class _TextViewState extends State<TextView> with WidgetsBindingObserver {
  late final TextViewModel _viewModel;
  bool _started = false;

  static const Color _accent = AppColors.textAccent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final locator = ServiceLocator.instance;
    _viewModel = TextViewModel(
      cameraService: locator.newCameraService(),
      permissionService: locator.permissions,
      tts: locator.tts,
      diagnostics: locator.diagnostics,
      preferences: locator.preferences,
      recognizeText: locator.newRecognizeTextUseCase(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Se informa al motor de voz de si TalkBack esta activo para que no se
    // solapen las dos locuciones.
    // Igual que en dinero: se avisa al motor de voz de que hay lector de
    // pantalla para que no se solapen.
    _viewModel.tts.setScreenReaderActive(
      MediaQuery.accessibleNavigationOf(context),
    );
    _viewModel.initialize();
  }

  @override
  // Misma politica que en la pantalla de dinero: nada sigue corriendo cuando
  // la aplicacion deja de estar en primer plano.
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
    return ChangeNotifierProvider<TextViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Consumer<TextViewModel>(
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
              final hasResult = vm.displayText.trim().isNotEmpty;

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
                                  painter: TextHighlightPainter(
                                    blocks: vm.blocks,
                                    color: _accent,
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
                        if (vm.status == RecognitionStatus.error)
                          const Positioned.fill(
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.all(28),
                                child: Text(
                                  AppStrings.cameraUnavailable,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
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
                            visible: analyzing && !hasResult,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Sin boton "nuevo": la busqueda se reanuda sola en cuanto
                  // la voz termina de leer. Un control que hay que ver para
                  // usarlo no sirve al usuario de esta aplicacion.
                  ResultPanel(
                    accent: _accent,
                    label: AppStrings.detectedTextLabel,
                    content: vm.displayText,
                  ),
                  BottomActionBar(
                    accent: _accent,
                    onHome: _goHome,
                    onRepeat: vm.repeatLast,
                    repeatEnabled: hasResult,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _statusLabel(TextViewModel vm) {
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
        return AppStrings.detectedTextLabel;
      case RecognitionStatus.notFound:
        return AppStrings.noTextFound;
      case RecognitionStatus.error:
        return AppStrings.cameraUnavailable;
      case RecognitionStatus.idle:
      case RecognitionStatus.searching:
      case RecognitionStatus.permissionDenied:
        return AppStrings.searchingText;
    }
  }
}
