// ==========================================================================
// ViewModel de INICIO
// Capa MVVM: Presentacion
//
// Bienvenida hablada y coordinacion con el lector de pantalla.
//
// Requisitos de la ERS que atiende:
//   - RNF-U1 TalkBack
// ==========================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_strings.dart';
import '../../data/services/tts_service.dart';

/// ViewModel de la pantalla de inicio.
///
/// Su unica responsabilidad es dar la bienvenida hablada la primera vez y
/// coordinar la salida de voz con el lector de pantalla.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel(this._tts);

  final TtsService _tts;
  bool _welcomed = false;

  Future<void> onScreenShown({required bool screenReaderActive}) async {
    _tts.setScreenReaderActive(screenReaderActive);
    await _tts.init();

    // Con TalkBack activo el propio lector anuncia la pantalla y los botones;
    // repetirlo con nuestro motor solo generaria dos voces superpuestas.
    if (screenReaderActive || _welcomed) return;

    _welcomed = true;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _tts.speakResult(AppStrings.homeWelcome, tag: 'welcome');
  }

  Future<void> onModuleSelected() async {
    HapticFeedback.mediumImpact();
    await _tts.stop();
  }
}
