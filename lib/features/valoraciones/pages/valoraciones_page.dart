import 'package:flutter/material.dart';

import '../../../core/storage/token_storage.dart';
import '../../authentication_security/pages/login/login_page.dart';
import '../models/valoracion_models.dart';
import '../services/valoracion_service.dart';
import '../widgets/atencion_pendiente_card.dart';
import '../widgets/valoracion_registrada_card.dart';
import '../widgets/valoraciones_vistas.dart';
import 'valorar_atencion_page.dart';

/// Pantalla principal del módulo CU40 — Valoración de la Clínica (Móvil).
///
/// Diseño coherente con la identidad Visión Clara:
/// - Tarjeta de resumen (pendientes, valoradas y promedio otorgado).
/// - Selector segmentado entre **Pendientes** y **Mis valoraciones**.
/// - Tarjetas dedicadas para registrar una nueva valoración o actualizar una
///   existente sin generar duplicados.
class ValoracionesPage extends StatefulWidget {
  const ValoracionesPage({
    super.key,
    this.valoracionService,
    this.onPendientesActualizados,
  });

  final ValoracionService? valoracionService;
  final ValueChanged<int>? onPendientesActualizados;

  @override
  State<ValoracionesPage> createState() => _ValoracionesPageState();
}

class _ValoracionesPageState extends State<ValoracionesPage>
    with SingleTickerProviderStateMixin {
  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _azulPrincipal = Color(0xFF1976D2);
  static const Color _grisTexto = Color(0xFF5C6F80);

  late final ValoracionService _service =
      widget.valoracionService ?? ValoracionService();

  ResumenValoracionesPaciente? _resumen;
  bool _cargando = true;
  String? _error;

  /// Sección visible: 0 = Pendientes, 1 = Mis valoraciones.
  int _seccion = 0;
  bool _seccionInicialAsignada = false;

  late final AnimationController _animacion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  late final Animation<double> _entrada = CurvedAnimation(
    parent: _animacion,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _animacion.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final resumen = await _service.obtenerResumen();
      if (!mounted) return;
      final cantidadPendientes = resumen.atenciones
          .where((a) => !a.estaValorada)
          .length;
      final cantidadValoradas = resumen.atenciones
          .where((a) => a.estaValorada)
          .length;

      setState(() {
        _resumen = resumen;
        _cargando = false;
        if (!_seccionInicialAsignada) {
          _seccion = (cantidadPendientes == 0 && cantidadValoradas > 0) ? 1 : 0;
          _seccionInicialAsignada = true;
        }
      });
      widget.onPendientesActualizados?.call(resumen.pendientes.length);
      _animacion.forward(from: 0);
    } on ValoracionException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) {
        await _cerrarSesionPorExpiracion();
        return;
      }
      setState(() {
        _error = error.message;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Ocurrió un error inesperado. Inténtalo de nuevo.';
        _cargando = false;
      });
    }
  }

  Future<void> _cerrarSesionPorExpiracion() async {
    await TokenStorage().deleteToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _abrirFormularioValoracion(AtencionValorable atencion) async {
    final resultado = await Navigator.of(context).push<ValoracionClinica>(
      MaterialPageRoute<ValoracionClinica>(
        builder: (_) => ValorarAtencionPage(
          consultaClinicaId: atencion.consultaClinicaId,
          oftalmologo: atencion.oftalmologo,
          fechaConsulta: atencion.fechaConsulta,
          motivoConsulta: atencion.motivoConsulta,
          tieneReceta: atencion.tieneReceta,
          empresaNombre: _resumen?.empresaNombre,
          valoracionExistente: atencion.valoracion,
          valoracionService: _service,
        ),
      ),
    );

    if (resultado != null && mounted) {
      final mensaje = resultado.mensaje?.trim().isNotEmpty == true
          ? resultado.mensaje!.trim()
          : (atencion.estaValorada
                ? 'Tu valoración fue actualizada correctamente.'
                : '¡Gracias! Tu valoración fue registrada correctamente.');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(child: Text(mensaje)),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: FondoValoraciones()),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _cargar,
              color: _azulPrincipal,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Valoración de la clínica',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: _azulProfundo,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _resumen?.empresaNombre?.trim().isNotEmpty == true
                                ? 'Califica tus atenciones en ${_resumen!.empresaNombre}'
                                : 'Expresa tu satisfacción tras cada atención médica',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _grisTexto,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _construirCuerpo(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirCuerpo() {
    if (_cargando) {
      return const ValoracionesCargando();
    }

    if (_error != null || _resumen == null) {
      return ValoracionesErrorVista(
        titulo: 'No se pudieron cargar tus valoraciones',
        mensaje: _error ?? 'Verifica tu conexión e inténtalo de nuevo.',
        onReintentar: _cargar,
      );
    }

    final resumen = _resumen!;
    final pendientes = resumen.atenciones
        .where((a) => !a.estaValorada)
        .toList();
    final valoradas = resumen.atenciones.where((a) => a.estaValorada).toList();

    final promedio = valoradas.isEmpty
        ? null
        : valoradas
                  .map((a) => a.valoracion!.puntuacion)
                  .reduce((a, b) => a + b) /
              valoradas.length;

    return FadeTransition(
      opacity: _entrada,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tarjetaResumen(
            pendientes: pendientes.length,
            valoradas: valoradas.length,
            promedio: promedio,
          ),
          const SizedBox(height: 16),
          _selectorSeccion(
            cantidadPendientes: pendientes.length,
            cantidadValoradas: valoradas.length,
          ),
          const SizedBox(height: 18),
          if (_seccion == 0)
            _construirListaPendientes(pendientes)
          else
            _construirListaValoradas(valoradas),
        ],
      ),
    );
  }

  Widget _tarjetaResumen({
    required int pendientes,
    required int valoradas,
    required double? promedio,
  }) {
    return Container(
      key: const Key('tarjeta_resumen_valoraciones'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: _azulPrincipal.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          _metricaItem(
            icono: Icons.notifications_active_outlined,
            colorIcono: const Color(0xFFD97706),
            etiqueta: 'Pendientes',
            valor: '$pendientes',
          ),
          _divisorVertical(),
          _metricaItem(
            icono: Icons.check_circle_outline,
            colorIcono: const Color(0xFF2E7D32),
            etiqueta: 'Valoradas',
            valor: '$valoradas',
          ),
          _divisorVertical(),
          _metricaItem(
            icono: Icons.star_rounded,
            colorIcono: const Color(0xFFF59E0B),
            etiqueta: 'Promedio',
            valor: promedio == null ? '—' : promedio.toStringAsFixed(1),
          ),
        ],
      ),
    );
  }

  Widget _metricaItem({
    required IconData icono,
    required Color colorIcono,
    required String etiqueta,
    required String valor,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icono, size: 22, color: colorIcono),
          const SizedBox(height: 6),
          Text(
            valor,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B2B3A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            etiqueta,
            style: const TextStyle(fontSize: 11.5, color: _grisTexto),
          ),
        ],
      ),
    );
  }

  Widget _divisorVertical() {
    return Container(
      width: 1,
      height: 40,
      color: const Color(0xFFE4EDF4),
    );
  }

  Widget _selectorSeccion({
    required int cantidadPendientes,
    required int cantidadValoradas,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD0E7F8)),
      ),
      child: Row(
        children: [
          _botonSegmento(
            key: const Key('tab_valoraciones_pendientes'),
            titulo: 'Pendientes ($cantidadPendientes)',
            activo: _seccion == 0,
            onTap: () => setState(() => _seccion = 0),
          ),
          _botonSegmento(
            key: const Key('tab_valoraciones_registradas'),
            titulo: 'Mis valoraciones ($cantidadValoradas)',
            activo: _seccion == 1,
            onTap: () => setState(() => _seccion = 1),
          ),
        ],
      ),
    );
  }

  Widget _botonSegmento({
    required Key key,
    required String titulo,
    required bool activo,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: activo ? _azulPrincipal : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
            child: Text(
              titulo,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: activo ? Colors.white : _azulProfundo,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirListaPendientes(List<AtencionValorable> pendientes) {
    if (pendientes.isEmpty) {
      return const ValoracionesVacioVista(
        icono: Icons.check_circle_outline_rounded,
        titulo: '¡Estás al día con tus valoraciones!',
        mensaje:
            'Cuando finalice una nueva revisión médica o recibas una receta, te llegará un mensaje aquí para calificar la atención recibida.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final atencion in pendientes)
          AtencionPendienteCard(
            atencion: atencion,
            onValorar: () => _abrirFormularioValoracion(atencion),
          ),
      ],
    );
  }

  Widget _construirListaValoradas(List<AtencionValorable> valoradas) {
    if (valoradas.isEmpty) {
      return const ValoracionesVacioVista(
        icono: Icons.rate_review_outlined,
        titulo: 'Aún no registraste valoraciones',
        mensaje:
            'Cuando califiques una atención médica aparecerá aquí y podrás consultarla o actualizarla en cualquier momento.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final atencion in valoradas)
          ValoracionRegistradaCard(
            atencion: atencion,
            onActualizar: () => _abrirFormularioValoracion(atencion),
          ),
      ],
    );
  }
}
