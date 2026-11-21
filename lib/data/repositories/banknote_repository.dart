// ==========================================================================
// Repositorio de dinero (billetes y monedas)
// Capa MVVM: Datos
//
// Implementa el contrato del dominio sobre DOS detectores TFLite
// independientes: uno de billetes y otro de monedas.
//
// Requisitos de la ERS que atiende:
//   - RF03 billetes y monedas
// ==========================================================================

import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../../domain/repositories/i_banknote_repository.dart';
import '../models/banknote_detection.dart';
import '../services/banknote_detector_service.dart';

/// Implementacion del contrato del dominio sobre los detectores TFLite.
///
/// Es una capa fina a proposito: su unica razon de ser es que el caso de uso
/// dependa de una interfaz y no del motor de inferencia concreto. Cambiar
/// TensorFlow Lite por otro motor se resuelve aqui, sin tocar dominio ni
/// presentacion.
///
/// ## Por que dos modelos y no uno
///
/// Los billetes y las monedas se entrenaron por separado. Juntarlos en un solo
/// modelo habria obligado a reentrenar el de billetes, que ya funciona bien
/// junto con la verificacion por OCR; se prefirio no arriesgar lo que ya
/// estaba resuelto.
///
/// ## Como se decide cual vale
///
/// No se intenta adivinar de antemano si lo que hay delante es un billete o
/// una moneda: **eso solo se sabe despues de analizar**. Los dos modelos miran
/// el mismo fotograma y despues se resuelven los desacuerdos.
///
/// El unico desacuerdo real ocurre cuando las dos cajas se solapan, es decir
/// cuando los dos modelos opinan sobre el MISMO objeto. Ahi se decide por la
/// forma de la caja: un billete colombiano es claramente alargado (unos 2 a 1)
/// y una moneda es redonda, asi que su caja es casi cuadrada. Si la forma no
/// desempata, gana la mayor confianza.
///
/// Cuando no hay solapamiento no se toca nada: las detecciones de billete
/// llegan al caso de uso exactamente como antes de existir el modulo de
/// monedas.
class BanknoteRepository implements IBanknoteRepository {
  BanknoteRepository(this._billetes, {BanknoteDetectorService? monedas})
      : _monedas = monedas;

  final BanknoteDetectorService _billetes;

  /// Detector de monedas. Opcional: si no se inyecta, el modulo se comporta
  /// igual que antes y solo reconoce billetes.
  final BanknoteDetectorService? _monedas;

  /// Relacion de lados (lado mayor sobre lado menor) a partir de la cual una
  /// caja se considera alargada, es decir propia de un billete.
  static const double _alargado = 1.45;

  /// Por debajo de esta relacion la caja se considera cuadrada, propia de una
  /// moneda.
  static const double _cuadrado = 1.25;

  /// Solape a partir del cual se entiende que las dos cajas senalan el mismo
  /// objeto y hay que quedarse con una sola.
  static const double _solapeMaximo = 0.35;

  /// Confianza a partir de la cual una caja alargada se da por billete sin
  /// consultar al otro modelo.
  static const double _confianzaEvidente = 0.80;

  @override
  Future<void> prepare() async {
    await _billetes.load();
    await _monedas?.load();
  }

  /// Basta con que UNO de los dos modelos haya cargado para que el modulo sea
  /// utilizable. Si falla el de monedas, la aplicacion sigue reconociendo
  /// billetes con normalidad.
  @override
  bool get isModelReady => _billetes.isReady || (_monedas?.isReady ?? false);

  @override
  String? get modelError =>
      isModelReady ? null : (_billetes.loadError ?? _monedas?.loadError);

  @override
  Future<List<BanknoteDetection>> detectFrame(
    CameraImage image,
    int rotationDegrees,
  ) async {
    final monedas = _monedas;

    // El detector se encarga del preprocesado completo (rotacion, letterbox y
    // normalizacion) en una sola pasada sobre el fotograma.
    final deBilletes = _billetes.isReady
        ? _billetes.detectFrame(image, rotationDegrees)
        : const <BanknoteDetection>[];

    // Si el modelo de billetes ya vio un billete sin margen de duda -- muy
    // convencido Y con una caja claramente alargada -- no hace falta gastar
    // una segunda inferencia preguntandole al de monedas. Es el caso mas
    // frecuente, y es el que mas se nota en la espera.
    if (_billeteEvidente(deBilletes, image, rotationDegrees)) return deBilletes;

    final deMonedas = (monedas != null && monedas.isReady)
        ? monedas.detectFrame(image, rotationDegrees)
        : const <BanknoteDetection>[];

    // Caso habitual: solo opino uno de los dos. No hay nada que arbitrar.
    if (deMonedas.isEmpty) return deBilletes;
    if (deBilletes.isEmpty) return deMonedas;

    return _resolver(deBilletes, deMonedas, image, rotationDegrees);
  }

  /// true si alguna deteccion de billete es tan clara que no merece la pena
  /// consultar tambien al modelo de monedas.
  bool _billeteEvidente(
    List<BanknoteDetection> billetes,
    CameraImage image,
    int rotationDegrees,
  ) {
    if (billetes.isEmpty) return false;

    final gira = rotationDegrees == 90 || rotationDegrees == 270;
    final anchoFrame = (gira ? image.height : image.width).toDouble();
    final altoFrame = (gira ? image.width : image.height).toDouble();

    for (final d in billetes) {
      if (d.confidence < _confianzaEvidente) continue;
      if (_relacionDeLados(d.rect, anchoFrame, altoFrame) >= _alargado) {
        return true;
      }
    }
    return false;
  }

  /// Resuelve los desacuerdos entre los dos modelos.
  List<BanknoteDetection> _resolver(
    List<BanknoteDetection> billetes,
    List<BanknoteDetection> monedas,
    CameraImage image,
    int rotationDegrees,
  ) {
    // Las cajas vienen normalizadas 0..1 sobre un fotograma que no es
    // cuadrado, asi que para conocer la forma REAL del objeto hay que
    // devolverles la proporcion del fotograma.
    final gira = rotationDegrees == 90 || rotationDegrees == 270;
    final anchoFrame = (gira ? image.height : image.width).toDouble();
    final altoFrame = (gira ? image.width : image.height).toDouble();

    final descartadas = <BanknoteDetection>{};

    for (final moneda in monedas) {
      for (final billete in billetes) {
        if (_iou(moneda.rect, billete.rect) <= _solapeMaximo) continue;

        // Las dos cajas senalan el mismo objeto: sobra una.
        final perdedora = _perdedora(
          moneda,
          billete,
          anchoFrame,
          altoFrame,
        );
        descartadas.add(perdedora);
        debugPrint(
          'ARBITRAJE ${billete.label} vs ${moneda.label} '
          '-> descartada ${perdedora.label}',
        );
      }
    }

    return [
      ...billetes.where((d) => !descartadas.contains(d)),
      ...monedas.where((d) => !descartadas.contains(d)),
    ];
  }

  /// Decide cual de las dos detecciones sobra, mirando primero la forma.
  BanknoteDetection _perdedora(
    BanknoteDetection moneda,
    BanknoteDetection billete,
    double anchoFrame,
    double altoFrame,
  ) {
    final forma = _relacionDeLados(billete.rect, anchoFrame, altoFrame);

    // Caja claramente alargada: es un billete, la moneda sobra.
    if (forma >= _alargado) return moneda;

    // Caja claramente cuadrada: es una moneda, el billete sobra.
    if (forma <= _cuadrado) return billete;

    // Zona intermedia (un billete muy inclinado, por ejemplo): la forma no
    // dice nada fiable, asi que decide la confianza.
    return moneda.confidence >= billete.confidence ? billete : moneda;
  }

  /// Lado mayor sobre lado menor de la caja, ya corregida la proporcion del
  /// fotograma. Siempre >= 1.
  static double _relacionDeLados(Rect rect, double anchoFrame, double altoFrame) {
    final ancho = rect.width * anchoFrame;
    final alto = rect.height * altoFrame;
    if (ancho <= 0 || alto <= 0) return 1;
    return ancho >= alto ? ancho / alto : alto / ancho;
  }

  static double _iou(Rect a, Rect b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    final w = right - left;
    final h = bottom - top;
    if (w <= 0 || h <= 0) return 0;
    final inter = w * h;
    final union = a.width * a.height + b.width * b.height - inter;
    return union <= 0 ? 0 : inter / union;
  }

  @override
  Future<void> release() async {
    _billetes.dispose();
    _monedas?.dispose();
  }
}
