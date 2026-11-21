// ==========================================================================
// Punto de entrada
// Capa MVVM: Arranque
//
// Prepara la orientacion, instala la captura global de errores y lanza la
// aplicacion. El motor de voz y el registro se preparan en segundo plano
// para no retrasar la primera pantalla.
//
// Requisitos de la ERS que atiende:
//   - RNF-R4 arranque <= 3 s
//   - RNF-F3 ningun cierre inesperado
//   - HU06 registro local de errores
// ==========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/di/service_locator.dart';

Future<void> main() async {
  // Toda la aplicacion se ejecuta dentro de una zona vigilada para que ningun
  // error no controlado cierre la aplicacion de forma abrupta: se registra
  // localmente y se sigue funcionando (RNF-F3, HU06).
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        ServiceLocator.instance.diagnostics.recordError(
          'flutter/${details.library ?? "desconocido"}',
          details.exception,
          details.stack,
        );
        FlutterError.presentError(details);
      };

      // Se accede al dispatcher a traves del binding para no importar dart:ui.
      WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
        ServiceLocator.instance.diagnostics
            .recordError('plataforma', error, stack);
        // true = el error queda tratado y la aplicacion no se cierra (RNF-F3).
        return true;
      };

      // La aplicacion se usa siempre en vertical: cambiar de orientacion
      // mientras se enfoca un billete desorienta y obliga a recalcular el
      // encuadre.
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      // El motor de voz y el registro se preparan EN SEGUNDO PLANO. Esperarlos
      // aqui retrasaba la primera pantalla y comprometia el RNF-R4 (listo para
      // capturar en menos de 3 segundos).
      ServiceLocator.instance.warmUp();

      runApp(const VisionApp());
    },
    (error, stack) {
      ServiceLocator.instance.diagnostics.recordError('zona', error, stack);
    },
  );
}
