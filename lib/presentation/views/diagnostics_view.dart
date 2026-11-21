// ==========================================================================
// Pantalla de diagnostico
// Capa MVVM: Presentacion
//
// Metricas frente a los requisitos de rendimiento y registro de hallazgos.
// Dirigida al desarrollador y al tester, no al usuario final.
//
// Requisitos de la ERS que atiende:
//   - RF08 diagnostico
//   - RF10 hallazgos
//   - CU08
//   - CU10
// ==========================================================================

import 'package:flutter/material.dart';

import '../../core/constants/app_dimens.dart';
import '../../core/constants/app_strings.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/diagnostics_service.dart';

/// Modo de diagnostico y registro de hallazgos (RF08 - CU08, RF10 - CU10).
///
/// Pantalla dirigida al desarrollador y al tester de accesibilidad, no al
/// usuario final: por eso se llega a ella con una pulsacion larga en el pie de
/// la pantalla de inicio y no ocupa sitio en la navegacion principal.
///
/// Todo lo que muestra procede del almacenamiento privado de la aplicacion.
/// No contiene imagenes, texto reconocido ni datos personales (RNF-S1).
class DiagnosticsView extends StatefulWidget {
  const DiagnosticsView({super.key});

  static const routeName = '/diagnostico';

  @override
  State<DiagnosticsView> createState() => _DiagnosticsViewState();
}

/// Estado de la pantalla de diagnostico.
///
/// Consulta el informe al entrar y lo refresca tras cada accion. No mantiene
/// copia propia de las metricas: la fuente unica es DiagnosticsService.
class _DiagnosticsViewState extends State<DiagnosticsView> {
  final DiagnosticsService _diag = ServiceLocator.instance.diagnostics;
  String _modelInfo = 'Consultando...';
  String? _lastExport;

  @override
  void initState() {
    super.initState();
    _diag.loadIfNeeded().then((_) {
      if (mounted) setState(() {});
    });
    ServiceLocator.instance.modelStorage.describe().then((d) {
      if (mounted) setState(() => _modelInfo = d);
    });
  }

  /// Vuelca el informe a un archivo dentro del area privada de la aplicacion.
  ///
  /// Solo salen metricas y hallazgos: ni imagenes, ni texto reconocido, ni nada
  /// que identifique al usuario.
  Future<void> _export() async {
    try {
      final ruta = await _diag.exportReport();
      if (!mounted) return;
      setState(() => _lastExport = ruta);
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastExport = 'Error al exportar: $e');
    }
  }

  /// Abre el formulario de hallazgo y lo registra si el tester lo confirma.
  Future<void> _addFinding() async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _FindingDialog(),
    );
    if (resultado == null) return;
    await _diag.addFinding(
      screen: resultado['screen'] as String,
      description: resultado['description'] as String,
      severity: resultado['severity'] as FindingSeverity,
      requirement: resultado['requirement'] as String,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final texto = _diag.statsFor(DiagnosticsService.textModule);
    final dinero = _diag.statsFor(DiagnosticsService.moneyModule);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onDark,
        title: const Text(AppStrings.diagnosticsTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.screenPadding),
          children: [
            _Section(
              title: 'Modo de diagnostico',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _diag.enabled,
                title: const Text(
                  'Registrar metricas de ejecucion',
                  style: TextStyle(color: AppColors.onDark),
                ),
                subtitle: const Text(
                  'Tiempos de inferencia y tasa de fallos, solo en este equipo',
                  style: TextStyle(color: AppColors.onDarkMuted, fontSize: 13),
                ),
                onChanged: (v) => setState(() => _diag.enabled = v),
              ),
            ),

            _Section(
              title: 'Modelo de billetes (RF07)',
              child: Text(
                _modelInfo,
                style: const TextStyle(color: AppColors.onDarkMuted, height: 1.4),
              ),
            ),

            _StatsCard(
              title: 'Texto - RNF-R1 (<= 2000 ms en el 90 %)',
              stats: texto,
              limitMs: 2000,
            ),
            _StatsCard(
              title: 'Billetes - RNF-R2 (<= 1500 ms en el 90 %)',
              stats: dinero,
              limitMs: 1500,
            ),

            _Section(
              title: 'Memoria - RNF-R5 (<= 350 MB)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Actual: ${_diag.memoryCurrentMb} MB\n'
                    'Pico:   ${_diag.memoryPeakMb} MB',
                    style: const TextStyle(
                      color: AppColors.onDark,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _diag.memoryPeakMb == 0
                        ? 'Sin datos todavia'
                        : (_diag.memoryPeakMb <= 350
                            ? 'CUMPLE el requisito'
                            : 'NO CUMPLE el requisito'),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _diag.memoryPeakMb == 0
                          ? AppColors.onDarkMuted
                          : (_diag.memoryPeakMb <= 350
                              ? AppColors.moneyAccent
                              : AppColors.error),
                    ),
                  ),
                ],
              ),
            ),

            _Section(
              title: 'Errores registrados (${_diag.errors.length})',
              child: _diag.errors.isEmpty
                  ? const Text(
                      'Ninguno. RNF-F3: 0 cierres inesperados.',
                      style: TextStyle(color: AppColors.onDarkMuted),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _diag.errors.reversed
                          .take(8)
                          .map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                e,
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),

            _Section(
              title: 'Hallazgos de pruebas (${_diag.findings.length})',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_diag.findings.isEmpty)
                    const Text(
                      'Sin hallazgos registrados.',
                      style: TextStyle(color: AppColors.onDarkMuted),
                    ),
                  ..._diag.findings.map(
                    (f) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        f.closed
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: f.closed
                            ? AppColors.moneyAccent
                            : _severityColor(f.severity),
                      ),
                      title: Text(
                        f.description,
                        style: const TextStyle(
                          color: AppColors.onDark,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        '${f.severity.name.toUpperCase()} · ${f.requirement} · ${f.screen}',
                        style: const TextStyle(
                          color: AppColors.onDarkMuted,
                          fontSize: 12,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.onDarkMuted),
                        onPressed: () async {
                          await _diag.removeFinding(f.id);
                          if (mounted) setState(() {});
                        },
                      ),
                      onTap: () async {
                        await _diag.toggleFindingClosed(f.id);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _addFinding,
                    icon: const Icon(Icons.add),
                    label: const Text('Registrar hallazgo'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.moneyAccent,
                      side: const BorderSide(color: AppColors.moneyAccent),
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.description_outlined),
              label: const Text('Exportar informe'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.textAccent,
                foregroundColor: AppColors.onAccent,
                minimumSize: const Size.fromHeight(62),
              ),
            ),
            if (_lastExport != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SelectableText(
                  'Informe guardado en:\n$_lastExport',
                  style: const TextStyle(
                    color: AppColors.onDarkMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static Color _severityColor(FindingSeverity s) {
    switch (s) {
      case FindingSeverity.baja:
        return AppColors.onDarkMuted;
      case FindingSeverity.media:
        return AppColors.warning;
      case FindingSeverity.alta:
      case FindingSeverity.critica:
        return AppColors.error;
    }
  }
}

/// Encabezado de seccion del informe.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.onDark,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Tarjeta con las metricas de un modulo (numero de lecturas, tiempo medio,
/// percentil 90 y fallos) contrastadas con el limite del requisito.
class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.title,
    required this.stats,
    required this.limitMs,
  });

  final String title;
  final ModuleStats stats;
  final int limitMs;

  @override
  Widget build(BuildContext context) {
    final cumple = stats.p90 > 0 && stats.p90 <= limitMs;
    return _Section(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Muestras', '${stats.samples}'),
          _row('Media', '${stats.average.round()} ms'),
          _row('Percentil 90', '${stats.p90} ms'),
          _row('Peor caso', '${stats.worst} ms'),
          _row('Fallos',
              '${stats.failures} (${(stats.failureRate * 100).toStringAsFixed(1)} %)'),
          const SizedBox(height: 8),
          Text(
            stats.samples == 0
                ? 'Sin datos todavia'
                : (cumple ? 'CUMPLE el requisito' : 'NO CUMPLE el requisito'),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: stats.samples == 0
                  ? AppColors.onDarkMuted
                  : (cumple ? AppColors.moneyAccent : AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: const TextStyle(color: AppColors.onDarkMuted, fontSize: 14)),
            Text(v,
                style: const TextStyle(
                    color: AppColors.onDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

/// Formulario de alta de un hallazgo de pruebas (RF10): pantalla, severidad,
/// requisito afectado y descripcion.
class _FindingDialog extends StatefulWidget {
  const _FindingDialog();

  @override
  State<_FindingDialog> createState() => _FindingDialogState();
}

/// Estado del formulario de hallazgos.
class _FindingDialogState extends State<_FindingDialog> {
  final _descripcion = TextEditingController();
  final _requisito = TextEditingController(text: 'RNF-U1');
  String _pantalla = 'Inicio';
  FindingSeverity _severidad = FindingSeverity.media;

  @override
  void dispose() {
    _descripcion.dispose();
    _requisito.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Nuevo hallazgo',
          style: TextStyle(color: AppColors.onDark)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _pantalla,
              dropdownColor: AppColors.surfaceAlt,
              decoration: const InputDecoration(labelText: 'Pantalla'),
              items: const ['Inicio', 'Texto', 'Dinero', 'Permisos']
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e,
                            style: const TextStyle(color: AppColors.onDark)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _pantalla = v ?? 'Inicio'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descripcion,
              maxLines: 3,
              style: const TextStyle(color: AppColors.onDark),
              decoration: const InputDecoration(labelText: 'Descripcion'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _requisito,
              style: const TextStyle(color: AppColors.onDark),
              decoration:
                  const InputDecoration(labelText: 'Requisito afectado'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<FindingSeverity>(
              initialValue: _severidad,
              dropdownColor: AppColors.surfaceAlt,
              decoration: const InputDecoration(labelText: 'Severidad'),
              items: FindingSeverity.values
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e.name,
                            style: const TextStyle(color: AppColors.onDark)),
                      ))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _severidad = v ?? FindingSeverity.media),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_descripcion.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'screen': _pantalla,
              'description': _descripcion.text.trim(),
              'severity': _severidad,
              'requirement': _requisito.text.trim(),
            });
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
