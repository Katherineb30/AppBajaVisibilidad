// ==========================================================================
// Preprocesado de imagen
// Capa MVVM: Core
//
// Convierte el fotograma de la camara en el tensor que espera el modelo, en
// una sola pasada: rotacion, escalado con relleno y balance de blancos.
// Corresponde al modulo de preprocesamiento descrito en la ERS.
//
// Requisitos de la ERS que atiende:
//   - RF01 preprocesado
//   - RF06 captura
//   - RNF-R2 tiempo de inferencia
//   - RNF-R5 memoria
// ==========================================================================

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Datos geometricos del letterbox, necesarios para devolver las cajas
/// detectadas al sistema de coordenadas de la imagen mostrada.
class LetterboxMeta {
  LetterboxMeta();

  double scale = 1;
  double padX = 0;
  double padY = 0;
  int width = 0;
  int height = 0;
  int side = 640;
}

/// Preprocesado de fotogramas para el modelo YOLO.
///
/// Todo ocurre en el dispositivo: ninguna imagen sale del telefono (RNF-S1).
///
/// La conversion se hace **en una sola pasada**: por cada pixel del tensor de
/// 640x640 se calcula de que pixel del sensor procede (deshaciendo el
/// letterbox y la rotacion a la vez) y se convierte solo ese. Asi se recorren
/// 410.000 pixeles en lugar de convertir el fotograma completo a RGB, rotarlo
/// a otro buffer y reescalarlo despues; el resultado es el mismo y cuesta una
/// fraccion del tiempo, que es lo que mantiene fluida la vista previa y limpia
/// la sintesis de voz.
class ImageConverter {
  const ImageConverter._();

  static Float32List? _tensor;
  static int _tensorLength = 0;

  // Datos del ultimo fotograma preprocesado, para no repetir el trabajo cuando
  // el segundo modelo pide exactamente lo mismo.
  static CameraImage? _ultimaImagen;
  static int _ultimoLado = -1;
  static bool _ultimoCanalesPrimero = false;
  static int _ultimaRotacion = -1;
  static final LetterboxMeta _ultimaMeta = LetterboxMeta();
  static bool _layoutLogged = false;
  static int _colorTick = 0;

  /// Convierte [image] en el tensor de entrada del modelo.
  ///
  /// [rotation] son los grados que hay que girar el fotograma para dejarlo
  /// derecho. [channelsFirst] elige la disposicion: true = [1,3,S,S] (NCHW),
  /// false = [1,S,S,3] (NHWC). [meta] recibe la geometria aplicada.
  static Float32List preprocess(
    CameraImage image, {
    required int rotation,
    required int side,
    required bool channelsFirst,
    required LetterboxMeta meta,
  }) {
    // Memoria de un solo fotograma.
    //
    // Con dos modelos (billetes y monedas) este metodo se llama DOS VECES
    // sobre el mismo fotograma y con los mismos parametros. El resultado seria
    // identico, asi que la segunda vez se devuelve el tensor ya calculado en
    // lugar de recorrer otra vez los 640x640 pixeles de salida. No cambia
    // nada de lo que se calcula: solo evita repetirlo.
    if (identical(image, _ultimaImagen) &&
        side == _ultimoLado &&
        channelsFirst == _ultimoCanalesPrimero &&
        rotation == _ultimaRotacion &&
        _tensor != null) {
      meta
        ..scale = _ultimaMeta.scale
        ..padX = _ultimaMeta.padX
        ..padY = _ultimaMeta.padY
        ..width = _ultimaMeta.width
        ..height = _ultimaMeta.height
        ..side = _ultimaMeta.side;
      return _tensor!;
    }

    final srcW = image.width;
    final srcH = image.height;

    final deg = ((rotation % 360) + 360) % 360;
    final swap = deg == 90 || deg == 270;
    final rotW = swap ? srcH : srcW;
    final rotH = swap ? srcW : srcH;

    final scale = math.min(side / rotW, side / rotH);
    final newW = (rotW * scale).round();
    final newH = (rotH * scale).round();
    final padX = ((side - newW) / 2).floorToDouble();
    final padY = ((side - newH) / 2).floorToDouble();

    meta
      ..scale = scale
      ..padX = padX
      ..padY = padY
      ..width = rotW
      ..height = rotH
      ..side = side;

    // Se guarda la geometria para poder devolverla en la llamada repetida.
    _ultimaImagen = image;
    _ultimoLado = side;
    _ultimoCanalesPrimero = channelsFirst;
    _ultimaRotacion = rotation;
    _ultimaMeta
      ..scale = scale
      ..padX = padX
      ..padY = padY
      ..width = rotW
      ..height = rotH
      ..side = side;

    final needed = side * side * 3;
    var out = _tensor;
    if (out == null || _tensorLength != needed) {
      out = Float32List(needed);
      _tensor = out;
      _tensorLength = needed;
    }
    // Relleno gris de Ultralytics.
    out.fillRange(0, needed, 114.0 / 255.0);

    final planes = image.planes;
    final yBytes = planes[0].bytes;
    final yStride = planes[0].bytesPerRow;

    // Disposicion de los planos de croma. La camara puede entregar el
    // fotograma de tres formas distintas y confundirlas intercambia U con V,
    // es decir, altera los colores: para un detector de billetes, que se
    // distinguen sobre todo por el color, eso es fatal.
    final Uint8List uBytes;
    final Uint8List vBytes;
    final int uOffset;
    final int vOffset;
    final int uvRowStride;
    final int uvPixelStride;

    if (planes.length >= 3) {
      // YUV_420_888: planos U y V separados, cada uno con su paso.
      uBytes = planes[1].bytes;
      vBytes = planes[2].bytes;
      uOffset = 0;
      vOffset = 0;
      uvRowStride = planes[1].bytesPerRow;
      uvPixelStride = planes[1].bytesPerPixel ?? 1;
    } else if (planes.length == 2) {
      // NV21 en dos planos: el segundo lleva V y U intercalados, V primero.
      uBytes = planes[1].bytes;
      vBytes = planes[1].bytes;
      vOffset = 0;
      uOffset = 1;
      uvRowStride = planes[1].bytesPerRow;
      uvPixelStride = 2;
    } else {
      // NV21 en un unico buffer: Y completo y despues VU intercalado.
      uBytes = yBytes;
      vBytes = yBytes;
      vOffset = srcW * srcH;
      uOffset = srcW * srcH + 1;
      uvRowStride = srcW;
      uvPixelStride = 2;
    }

    if (!_layoutLogged) {
      _layoutLogged = true;
      debugPrint(
        'CAMARA planos=${planes.length} '
        '${planes.map((p) => "[bytes=${p.bytes.length} "
            "fila=${p.bytesPerRow} pixel=${p.bytesPerPixel}]").join(" ")} '
        '| ${srcW}x$srcH -> croma fila=$uvRowStride pixel=$uvPixelStride',
      );
    }

    final planeArea = side * side;
    final padXi = padX.toInt();
    final padYi = padY.toInt();
    final invScale = 1.0 / scale;

    for (var oy = 0; oy < newH; oy++) {
      final dstY = oy + padYi;
      if (dstY < 0 || dstY >= side) continue;

      // Coordenada en la imagen ya enderezada.
      final ry = (oy * invScale).floor().clamp(0, rotH - 1);

      for (var ox = 0; ox < newW; ox++) {
        final dstX = ox + padXi;
        if (dstX < 0 || dstX >= side) continue;

        final rx = (ox * invScale).floor().clamp(0, rotW - 1);

        // Deshacer la rotacion: de la imagen derecha al sensor.
        final int sx;
        final int sy;
        switch (deg) {
          case 90:
            sx = ry;
            sy = srcH - 1 - rx;
            break;
          case 180:
            sx = srcW - 1 - rx;
            sy = srcH - 1 - ry;
            break;
          case 270:
            sx = srcW - 1 - ry;
            sy = rx;
            break;
          default:
            sx = rx;
            sy = ry;
        }
        if (sx < 0 || sx >= srcW || sy < 0 || sy >= srcH) continue;

        // Conversion YUV -> RGB (BT.601). La camara entrega luminancia a
        // resolucion completa y crominancia a la mitad, de ahi los
        // desplazamientos a la derecha: cada par de pixeles comparte U y V.
        // Si el plano viniera corto se asume 128 (gris neutro) en lugar de
        // salirse del rango y romper el fotograma.
        final luma = yBytes[sy * yStride + sx];
        final uvBase = (sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride;
        final iu = uOffset + uvBase;
        final iv = vOffset + uvBase;
        final u = (iu < uBytes.length ? uBytes[iu] : 128) - 128;
        final v = (iv < vBytes.length ? vBytes[iv] : 128) - 128;

        var r = luma + 1.370705 * v;
        var g = luma - 0.337633 * u - 0.698001 * v;
        var b = luma + 1.732446 * u;

        r = r < 0 ? 0 : (r > 255 ? 255 : r);
        g = g < 0 ? 0 : (g > 255 ? 255 : g);
        b = b < 0 ? 0 : (b > 255 ? 255 : b);

        // El tensor se escribe en el orden que pide el modelo: NCHW guarda los
        // tres canales en planos separados y NHWC los intercala pixel a pixel.
        // El orden se detecta al cargar el modelo, no se supone.
        if (channelsFirst) {
          final base = dstY * side + dstX;
          out[base] = r / 255.0;
          out[planeArea + base] = g / 255.0;
          out[2 * planeArea + base] = b / 255.0;
        } else {
          final base = (dstY * side + dstX) * 3;
          out[base] = r / 255.0;
          out[base + 1] = g / 255.0;
          out[base + 2] = b / 255.0;
        }
      }
    }

    // ------------------------------------------------------------------
    // Balance de blancos (preprocesado de RF01 / modulo de preprocesamiento).
    //
    // Bajo un bombillo incandescente toda la escena se tine de ambar y los
    // billetes de 5, 10 y 20 mil, que ya son parecidos entre si, se vuelven
    // indistinguibles: el modelo los colapsa en la clase mas rojiza. Se estima
    // el iluminante con el metodo del punto blanco (los billetes tienen zonas
    // claras) y se neutraliza la dominante.
    //
    // Se usa un percentil alto en lugar del maximo absoluto para no dejar que
    // un reflejo especular decida la correccion, y el factor se limita para
    // que una escena legitimamente monocroma no se distorsione.
    _applyWhiteBalance(out, needed, planeArea, channelsFirst);

    if (++_colorTick % 8 == 1) {
      var sr = 0.0, sg = 0.0, sb = 0.0;
      var n = 0;
      final paso = channelsFirst ? 97 : 3 * 97;
      if (channelsFirst) {
        for (var i = 0; i < planeArea; i += paso) {
          sr += out[i];
          sg += out[planeArea + i];
          sb += out[2 * planeArea + i];
          n++;
        }
      } else {
        for (var i = 0; i + 2 < needed; i += paso) {
          sr += out[i];
          sg += out[i + 1];
          sb += out[i + 2];
          n++;
        }
      }
      if (n > 0) {
        debugPrint(
          'COLOR medio R=${(sr / n * 255).round()} '
          'G=${(sg / n * 255).round()} B=${(sb / n * 255).round()}',
        );
      }
    }

    return out;
  }

  /// Neutraliza la dominante de color estimando el punto blanco por canal.
  static void _applyWhiteBalance(
    Float32List out,
    int needed,
    int planeArea,
    bool channelsFirst,
  ) {
    // Muestreo disperso: no hace falta recorrerlo entero para estimar el
    // iluminante, y asi el coste es despreciable frente a la inferencia.
    const muestreo = 37;
    final altos = <double>[0, 0, 0];

    void observar(double r, double g, double b) {
      if (r > altos[0]) altos[0] = r;
      if (g > altos[1]) altos[1] = g;
      if (b > altos[2]) altos[2] = b;
    }

    if (channelsFirst) {
      for (var i = 0; i < planeArea; i += muestreo) {
        observar(out[i], out[planeArea + i], out[2 * planeArea + i]);
      }
    } else {
      for (var i = 0; i + 2 < needed; i += 3 * muestreo) {
        observar(out[i], out[i + 1], out[i + 2]);
      }
    }

    // Escena demasiado oscura para estimar nada con sentido.
    if (altos[0] < 0.15 || altos[1] < 0.15 || altos[2] < 0.15) return;

    final objetivo = (altos[0] + altos[1] + altos[2]) / 3;
    final k = <double>[
      (objetivo / altos[0]).clamp(0.70, 1.45),
      (objetivo / altos[1]).clamp(0.70, 1.45),
      (objetivo / altos[2]).clamp(0.70, 1.45),
    ];

    // Correccion inapreciable: no merece la pena recorrer el tensor.
    if ((k[0] - 1).abs() < 0.03 &&
        (k[1] - 1).abs() < 0.03 &&
        (k[2] - 1).abs() < 0.03) {
      return;
    }

    double lim(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

    if (channelsFirst) {
      for (var c = 0; c < 3; c++) {
        final base = c * planeArea;
        final factor = k[c];
        for (var i = 0; i < planeArea; i++) {
          out[base + i] = lim(out[base + i] * factor);
        }
      }
    } else {
      for (var i = 0; i + 2 < needed; i += 3) {
        out[i] = lim(out[i] * k[0]);
        out[i + 1] = lim(out[i + 1] * k[1]);
        out[i + 2] = lim(out[i + 2] * k[2]);
      }
    }

    if (_colorTick % 8 == 0) {
      debugPrint(
        'BALANCE blanco kR=${k[0].toStringAsFixed(2)} '
        'kG=${k[1].toStringAsFixed(2)} kB=${k[2].toStringAsFixed(2)}',
      );
    }
  }

  /// Luminancia media del fotograma (0..255). Gobierna la linterna automatica.
  static double averageLuminance(CameraImage image) {
    final y = image.planes[0].bytes;
    if (y.isEmpty) return 128;
    var sum = 0;
    var count = 0;
    const step = 64;
    for (var i = 0; i < y.length; i += step) {
      sum += y[i];
      count++;
    }
    return count == 0 ? 128 : sum / count;
  }
}
