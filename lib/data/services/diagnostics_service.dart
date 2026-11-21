// ==========================================================================
// Diagnostico y hallazgos
// Capa MVVM: Datos
//
// Metricas de ejecucion, registro de errores y hallazgos de pruebas, todo en
// el area privada de la aplicacion y sin imagenes ni texto reconocido.
//
// Requisitos de la ERS que atiende:
//   - RF08 modo de diagnostico
//   - RF10 registro de hallazgos
//   - RNF-R1
//   - RNF-R2
//   - RNF-R5
// ==========================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Severidad de un hallazgo de pruebas (RF10).
enum FindingSeverity { baja, media, alta, critica }

/// Hallazgo registrado durante las pruebas de accesibilidad (RF10 - CU10).
class Finding {
  Finding({
    required this.id,
    required this.screen,
    required this.description,
    required this.severity,
    required this.requirement,
    required this.createdAt,
    this.closed = false,
  });

  final String id;
  final String screen;
  final String description;
  final FindingSeverity severity;

  /// Requisito afectado, por ejemplo "RNF-U1".
  final String requirement;

  final DateTime createdAt;
  bool closed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'screen': screen,
        'description': description,
        'severity': severity.name,
        'requirement': requirement,
        'createdAt': createdAt.toIso8601String(),
        'closed': closed,
      };

  static Finding fromJson(Map<String, dynamic> j) => Finding(
        id: j['id'] as String,
        screen: j['screen'] as String,
        description: j['description'] as String,
        severity: FindingSeverity.values.firstWhere(
          (s) => s.name == j['severity'],
          orElse: () => FindingSeverity.media,
        ),
        requirement: j['requirement'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        closed: j['closed'] as bool? ?? false,
      );
}

/// Estadisticas de un modulo de reconocimiento.
class ModuleStats {
  ModuleStats(this.module);

  final String module;
  final List<int> _millis = [];
  int _failures = 0;

  void add(int ms, bool ok) {
    if (ok) {
      _millis.add(ms);
      // Ventana deslizante: interesa el comportamiento reciente, no el
      // historico completo, y evita que la lista crezca sin limite.
      if (_millis.length > 200) _millis.removeAt(0);
    } else {
      _failures++;
    }
  }

  int get samples => _millis.length;
  int get failures => _failures;

  double get average =>
      _millis.isEmpty ? 0 : _millis.reduce((a, b) => a + b) / _millis.length;

  /// Percentil 90: es la metrica que piden RNF-R1 y RNF-R2
  /// ("en el 90 % de las capturas").
  int get p90 {
    if (_millis.isEmpty) return 0;
    final sorted = [..._millis]..sort();
    final index = ((sorted.length - 1) * 0.9).round();
    return sorted[index];
  }

  int get worst => _millis.isEmpty ? 0 : _millis.reduce((a, b) => a > b ? a : b);

  double get failureRate {
    final total = _millis.length + _failures;
    return total == 0 ? 0 : _failures / total;
  }

  Map<String, dynamic> toJson() => {
        'modulo': module,
        'muestras': samples,
        'fallos': failures,
        'media_ms': average.round(),
        'p90_ms': p90,
        'peor_ms': worst,
        'tasa_fallo': double.parse(failureRate.toStringAsFixed(4)),
      };
}

/// Modo de diagnostico y registro local (RF08 - CU08, RF10 - CU10, HU06).
///
/// Registra tiempos de inferencia, fallos de reconocimiento y errores no
/// controlados **solo en el almacenamiento privado de la aplicacion**. Nunca
/// se guarda ninguna imagen ni el texto reconocido, y nada sale del
/// dispositivo (RNF-S1).
class DiagnosticsService {
  DiagnosticsService();

  static const String textModule = 'texto';
  static const String moneyModule = 'billetes';

  final Map<String, ModuleStats> _stats = {};
  final List<int> _memoriaMb = [];
  final List<String> _errors = [];
  final List<Finding> _findings = [];

  /// El modo de diagnostico se puede encender y apagar desde la pantalla de
  /// diagnostico (RF08). Arranca activo en depuracion.
  bool enabled = kDebugMode;

  bool _loaded = false;
  DateTime _sessionStart = DateTime.now();

  List<String> get errors => List.unmodifiable(_errors);
  List<Finding> get findings => List.unmodifiable(_findings);

  ModuleStats statsFor(String module) =>
      _stats.putIfAbsent(module, () => ModuleStats(module));

  // ------------------------------------------------------------------
  // Registro
  // ------------------------------------------------------------------

  /// Tiempo que tardo un reconocimiento completo, y si produjo resultado.
  void recordRecognition(String module, int millis, {required bool success}) {
    if (!enabled) return;
    statsFor(module).add(millis, success);
    _sampleMemory();
  }

  /// Memoria residente del proceso, en MB (RF08, RNF-R5 <= 350 MB).
  void _sampleMemory() {
    try {
      final mb = ProcessInfo.currentRss ~/ (1024 * 1024);
      if (mb <= 0) return;
      _memoriaMb.add(mb);
      if (_memoriaMb.length > 200) _memoriaMb.removeAt(0);
    } catch (_) {
      // ProcessInfo no esta disponible en todas las plataformas.
    }
  }

  int get memoryCurrentMb => _memoriaMb.isEmpty ? 0 : _memoriaMb.last;
  int get memoryPeakMb =>
      _memoriaMb.isEmpty ? 0 : _memoriaMb.reduce((a, b) => a > b ? a : b);

  /// Error controlado o excepcion no capturada (RNF-F3, HU06).
  void recordError(String where, Object error, [StackTrace? stack]) {
    final line = '${DateTime.now().toIso8601String()} | $where | $error';
    _errors.add(line);
    if (_errors.length > 100) _errors.removeAt(0);
    debugPrint('DIAGNOSTICO: $line');
    // Se persiste siempre, incluso con el modo apagado: un fallo perdido no
    // se puede diagnosticar despues.
    unawaited(_appendToLog(line));
  }

  Future<void> addFinding({
    required String screen,
    required String description,
    required FindingSeverity severity,
    required String requirement,
  }) async {
    await _load();
    _findings.add(
      Finding(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        screen: screen,
        description: description,
        severity: severity,
        requirement: requirement,
        createdAt: DateTime.now(),
      ),
    );
    await _saveFindings();
  }

  Future<void> toggleFindingClosed(String id) async {
    final f = _findings.firstWhere((x) => x.id == id);
    f.closed = !f.closed;
    await _saveFindings();
  }

  Future<void> removeFinding(String id) async {
    _findings.removeWhere((x) => x.id == id);
    await _saveFindings();
  }

  // ------------------------------------------------------------------
  // Persistencia (area privada de la aplicacion)
  // ------------------------------------------------------------------

  Future<Directory> _dir() async => getApplicationDocumentsDirectory();

  Future<File> _findingsFile() async =>
      File('${(await _dir()).path}/hallazgos.json');

  Future<File> _logFile() async => File('${(await _dir()).path}/errores.log');

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _findingsFile();
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString()) as List<dynamic>;
        _findings
          ..clear()
          ..addAll(
            data.map((e) => Finding.fromJson(e as Map<String, dynamic>)),
          );
      }
    } catch (e) {
      debugPrint('DiagnosticsService: no se pudieron leer los hallazgos -> $e');
    }
  }

  Future<void> loadIfNeeded() => _load();

  Future<void> _saveFindings() async {
    try {
      final f = await _findingsFile();
      await f.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert(_findings.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('DiagnosticsService: no se pudieron guardar hallazgos -> $e');
    }
  }

  Future<void> _appendToLog(String line) async {
    try {
      final f = await _logFile();
      await f.writeAsString('$line\n', mode: FileMode.append);
    } catch (_) {
      // Si no se puede escribir el registro, la aplicacion sigue funcionando:
      // el diagnostico nunca debe ser causa de un fallo.
    }
  }

  // ------------------------------------------------------------------
  // Informe exportable (RF08, RF10)
  // ------------------------------------------------------------------

  String buildReport() {
    final b = StringBuffer()
      ..writeln('INFORME DE DIAGNOSTICO - VisionApp')
      ..writeln('Generado: ${DateTime.now()}')
      ..writeln('Sesion iniciada: $_sessionStart')
      ..writeln('')
      ..writeln('--- RENDIMIENTO ---');

    if (_stats.isEmpty) {
      b.writeln('Sin muestras registradas.');
    }
    for (final s in _stats.values) {
      final limite = s.module == textModule ? 2000 : 1500;
      final requisito = s.module == textModule ? 'RNF-R1' : 'RNF-R2';
      final cumple = s.p90 > 0 && s.p90 <= limite;
      b
        ..writeln('Modulo: ${s.module}')
        ..writeln('  muestras      : ${s.samples}')
        ..writeln('  media         : ${s.average.round()} ms')
        ..writeln('  percentil 90  : ${s.p90} ms')
        ..writeln('  peor caso     : ${s.worst} ms')
        ..writeln('  fallos        : ${s.failures} '
            '(${(s.failureRate * 100).toStringAsFixed(1)} %)')
        ..writeln('  $requisito (<= $limite ms en el 90 %): '
            '${cumple ? "CUMPLE" : "NO CUMPLE"}')
        ..writeln('');
    }

    b
      ..writeln('--- MEMORIA (RNF-R5 <= 350 MB) ---')
      ..writeln('  actual : $memoryCurrentMb MB')
      ..writeln('  pico   : $memoryPeakMb MB')
      ..writeln('  veredicto: ${memoryPeakMb == 0 ? "sin datos" : (memoryPeakMb <= 350 ? "CUMPLE" : "NO CUMPLE")}')
      ..writeln('')
      ..writeln('--- ERRORES REGISTRADOS (${_errors.length}) ---');
    if (_errors.isEmpty) b.writeln('Ninguno.');
    for (final e in _errors) {
      b.writeln(e);
    }

    b
      ..writeln('')
      ..writeln('--- HALLAZGOS DE PRUEBAS (${_findings.length}) ---');
    if (_findings.isEmpty) b.writeln('Ninguno.');
    for (final f in _findings) {
      b.writeln('[${f.closed ? "CERRADO" : "ABIERTO"}] '
          '${f.severity.name.toUpperCase()} | ${f.requirement} | '
          '${f.screen} | ${f.description} | ${f.createdAt}');
    }

    b
      ..writeln('')
      ..writeln('Nota: este informe no contiene imagenes, texto reconocido ni '
          'datos personales (RNF-S1).');
    return b.toString();
  }

  /// Escribe el informe en el area privada y devuelve la ruta.
  Future<String> exportReport() async {
    final marca = DateTime.now().toIso8601String().replaceAll(':', '-');
    final f = File('${(await _dir()).path}/diagnostico_$marca.txt');
    await f.writeAsString(buildReport());
    return f.path;
  }

  void resetSession() {
    _stats.clear();
    _memoriaMb.clear();
    _sessionStart = DateTime.now();
  }
}
