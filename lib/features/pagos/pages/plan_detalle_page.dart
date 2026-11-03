import 'package:flutter/material.dart';

import '../../../core/storage/token_storage.dart';
import '../../authentication_security/pages/login/login_page.dart';
import '../models/pago_models.dart';
import '../models/planes_cuotas_models.dart';
import '../services/pagos_service.dart';
import '../services/planes_cuotas_service.dart';
import '../services/stripe_payment_service.dart';
import '../widgets/cuota_plan_card.dart';
import '../widgets/estado_pago_chip.dart';
import '../widgets/estado_plan_chip.dart';
import '../widgets/pagos_vistas.dart';
import 'pagar_cuota_page.dart';

/// Detalle de un plan de pago del paciente (CU33).
///
/// Muestra el resumen del financiamiento, el estado del plan, los servicios
/// financiados y el cronograma de cuotas con su estado real. Cada cuota
/// cobrable ofrece la acción "Pagar esta cuota".
///
/// Todos los datos provienen de `GET /pagos/mis-planes/{plan_id}`; la app no
/// calcula intereses, recargos ni abonos parciales.
class PlanDetallePage extends StatefulWidget {
  const PlanDetallePage({
    super.key,
    required this.planId,
    this.planesService,
    this.stripeService,
    this.alCerrarSesion,
    this.maxVerificaciones = 5,
    this.esperaVerificacion = const Duration(seconds: 2),
  });

  /// Identificador del plan a consultar.
  final int planId;

  /// Servicio de CU32/CU33; inyectable en pruebas.
  final PlanesCuotasService? planesService;

  /// Servicio de Stripe; inyectable en pruebas.
  final StripePaymentService? stripeService;

  /// Acción de cierre de sesión ante un JWT inválido o expirado.
  final Future<void> Function()? alCerrarSesion;

  /// Número máximo de consultas de estado tras un intento de pago.
  final int maxVerificaciones;

  /// Espera entre consultas de estado.
  final Duration esperaVerificacion;

  @override
  State<PlanDetallePage> createState() => _PlanDetallePageState();
}

class _PlanDetallePageState extends State<PlanDetallePage> {
  late final PlanesCuotasService _planesService =
      widget.planesService ?? PlanesCuotasService();

  PlanPago? _plan;
  bool _cargando = true;
  String? _error;

  /// Evita consultas simultáneas del mismo plan.
  bool _enCurso = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Carga el plan con su cronograma (operación de SOLO LECTURA).
  Future<void> _cargar({bool silencioso = false}) async {
    if (_enCurso) return;
    _enCurso = true;

    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }

    try {
      final PlanPago plan = await _planesService.consultarMiPlan(
        widget.planId,
      );

      if (!mounted) return;
      setState(() {
        _plan = plan;
        _cargando = false;
        _error = null;
      });
    } on PagosException catch (error) {
      if (!mounted) return;

      if (error.statusCode == 401) {
        await _cerrarSesion();
        return;
      }

      setState(() {
        _cargando = false;
        if (!silencioso || _plan == null) {
          _error = error.message;
        }
      });
    } finally {
      _enCurso = false;
    }
  }

  /// Cierra la sesión local y vuelve al Login.
  Future<void> _cerrarSesion() async {
    final Future<void> Function()? alCerrar = widget.alCerrarSesion;

    if (alCerrar != null) {
      await alCerrar();
    } else {
      await TokenStorage().deleteToken();
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  /// Abre el resumen de pago de una cuota y refresca al volver.
  Future<void> _pagarCuota(PlanPago plan, CuotaPlan cuota) async {
    final bool? aprobado = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PagarCuotaPage(
          plan: plan,
          cuota: cuota,
          planesService: _planesService,
          stripeService: widget.stripeService,
          alCerrarSesion: widget.alCerrarSesion,
          maxVerificaciones: widget.maxVerificaciones,
          esperaVerificacion: widget.esperaVerificacion,
        ),
      ),
    );

    if (!mounted) return;

    // Se recarga SIEMPRE: el backend es la fuente de verdad del estado.
    await _cargar(silencioso: true);

    if (!mounted || aprobado != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pago de la cuota confirmado.')),
    );
  }

  /// Muestra los intentos registrados de la cuota según el backend.
  Future<void> _verIntentos(CuotaPlan cuota) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _IntentosSheet(
        cuotaId: cuota.id,
        numeroCuota: cuota.numeroCuota,
        planesService: _planesService,
      ),
    );

    if (!mounted) return;
    await _cargar(silencioso: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0D47A1),
        elevation: 0,
        title: const Text('Detalle del plan'),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: FondoPagos()),
          SafeArea(
            top: false,
            child: RefreshIndicator(
              color: const Color(0xFF1976D2),
              onRefresh: () => _cargar(silencioso: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                children: [_contenido()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Carga, error o contenido del plan.
  Widget _contenido() {
    if (_cargando) {
      return const PagosCargando(mensaje: 'Cargando el plan de pago...');
    }

    final PlanPago? plan = _plan;

    if (_error != null || plan == null) {
      return PagosErrorVista(
        titulo: 'No se pudo cargar el plan',
        mensaje: _error ?? 'No se encontró el plan de pago.',
        onReintentar: _cargar,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _resumen(plan),
        const SizedBox(height: 18),
        const Text(
          'Mis cuotas',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0D47A1),
          ),
        ),
        const SizedBox(height: 12),
        for (final cuota in plan.cuotas)
          CuotaPlanCard(
            cuota: cuota,
            totalCuotas: plan.cantidadCuotas,
            moneda: plan.moneda,
            pagable: cuota.esPagableEn(plan.estado),
            onPagar: () => _pagarCuota(plan, cuota),
            onVerIntentos: () => _verIntentos(cuota),
          ),
        const SizedBox(height: 6),
        _servicios(plan),
      ],
    );
  }

  /// Resumen del financiamiento con el estado real del plan.
  Widget _resumen(PlanPago plan) {
    return _TarjetaPlan(
      hijos: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Plan de pago #${plan.id}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF0D47A1),
                ),
              ),
            ),
            const SizedBox(width: 8),
            EstadoPlanChip(estado: plan.estado),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Resumen del financiamiento',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF0D47A1),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ImportePlan(
                titulo: 'Total del plan',
                valor: formatearMontoConMoneda(plan.moneda, plan.montoTotal),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ImportePlan(
                titulo: 'Saldo pendiente',
                valor: formatearMontoConMoneda(
                  plan.moneda,
                  plan.saldoPendiente,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Consulta clínica #${plan.consultaClinicaId} · '
          '${plan.cantidadCuotas} cuotas programadas',
          style: const TextStyle(color: Color(0xFF5C6F80), fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '${plan.cuotasPagadas} de ${plan.cantidadCuotas} '
                'cuotas pagadas',
                style: const TextStyle(
                  color: Color(0xFF5C6F80),
                  fontSize: 12.5,
                ),
              ),
            ),
            Text(
              '${plan.porcentaje} %',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
                color: Color(0xFF0D47A1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: plan.progreso,
            minHeight: 8,
            backgroundColor: const Color(0xFFE3EDF7),
            valueColor: const AlwaysStoppedAnimation<Color>(
              Color(0xFF1976D2),
            ),
          ),
        ),
        if (!plan.admiteNuevosPagos) ...[
          const SizedBox(height: 14),
          const _Aviso(
            icono: Icons.info_outline,
            texto: 'Este plan no admite nuevos pagos de cuotas.',
            color: Color(0xFF1565C0),
            fondo: Color(0xFFE3F1FC),
          ),
        ],
        if (plan.tieneCuotasVencidas) ...[
          const SizedBox(height: 10),
          const _Aviso(
            icono: Icons.warning_amber_rounded,
            texto: 'Tienes cuotas vencidas. Puedes pagarlas desde esta lista.',
            color: Color(0xFFB3261E),
            fondo: Color(0xFFFDECEC),
          ),
        ],
      ],
    );
  }

  /// Servicios financiados por el plan (los entrega el backend).
  Widget _servicios(PlanPago plan) {
    return _TarjetaPlan(
      hijos: [
        const Row(
          children: [
            Icon(Icons.medical_services_outlined, size: 20, color: Color(0xFF1976D2)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Servicios incluidos',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0D47A1),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (plan.servicios.isEmpty)
          const Text(
            'El backend no reporta servicios financiados para este plan.',
            style: TextStyle(color: Color(0xFF5C6F80), fontSize: 12.5),
          )
        else
          for (final servicio in plan.servicios)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      servicio.nombreServicio,
                      style: const TextStyle(
                        color: Color(0xFF3A4A5A),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatearMontoConMoneda(
                      plan.moneda,
                      servicio.montoFinanciado,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF0D47A1),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// Contenedor blanco redondeado con la identidad visual del módulo Pagos.
class _TarjetaPlan extends StatelessWidget {
  const _TarjetaPlan({required this.hijos});

  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: hijos,
      ),
    );
  }
}

/// Importe con su etiqueta.
class _ImportePlan extends StatelessWidget {
  const _ImportePlan({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(color: Color(0xFF5C6F80), fontSize: 11.5),
        ),
        const SizedBox(height: 3),
        Text(
          valor,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: Color(0xFF0D47A1),
          ),
        ),
      ],
    );
  }
}

/// Aviso corto con ícono y color de énfasis.
class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icono,
    required this.texto,
    required this.color,
    required this.fondo,
  });

  final IconData icono;
  final String texto;
  final Color color;
  final Color fondo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel con los intentos de pago registrados de una cuota.
///
/// Consulta `GET /pagos/cuotas/{cuota_id}/intentos`: el backend decide qué
/// intentos existen y su estado; la app solo los muestra.
class _IntentosSheet extends StatefulWidget {
  const _IntentosSheet({
    required this.cuotaId,
    required this.numeroCuota,
    required this.planesService,
  });

  final int cuotaId;
  final int numeroCuota;
  final PlanesCuotasService planesService;

  @override
  State<_IntentosSheet> createState() => _IntentosSheetState();
}

class _IntentosSheetState extends State<_IntentosSheet> {
  late Future<IntentosCuota> _futuro = widget.planesService.listarIntentos(
    widget.cuotaId,
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Intentos de la cuota ${widget.numeroCuota}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0D47A1),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: FutureBuilder<IntentosCuota>(
                future: _futuro,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const PagosCargando(
                      mensaje: 'Consultando los intentos de pago...',
                    );
                  }

                  if (snapshot.hasError) {
                    final Object? error = snapshot.error;
                    final String mensaje = error is PagosException
                        ? error.message
                        : 'No se pudieron consultar los intentos de pago.';

                    return PagosErrorVista(
                      titulo: 'No se pudieron obtener los intentos',
                      mensaje: mensaje,
                      onReintentar: () => setState(() {
                        _futuro = widget.planesService.listarIntentos(
                          widget.cuotaId,
                        );
                      }),
                    );
                  }

                  final IntentosCuota? datos = snapshot.data;

                  if (datos == null || datos.intentos.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'No hay intentos de pago registrados para esta cuota.',
                        style: TextStyle(color: Color(0xFF5C6F80)),
                      ),
                    );
                  }

                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final intento in datos.intentos)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              EstadoPagoChip(estado: intento.estado),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      intento.metodoPagoEtiqueta,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF3A4A5A),
                                      ),
                                    ),
                                    Text(
                                      formatearFechaHoraBolivia(
                                        intento.fechaCreacion,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF5C6F80),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                formatearMonto(intento.monto),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0D47A1),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

