import 'package:flutter/material.dart';

import '../../../core/storage/token_storage.dart';
import '../../authentication_security/pages/login/login_page.dart';
import '../models/pago_models.dart';
import '../models/planes_cuotas_models.dart';
import '../services/pagos_service.dart';
import '../services/planes_cuotas_service.dart';
import '../services/stripe_payment_service.dart';
import '../widgets/pagos_vistas.dart';

/// Pantalla de pago de una cuota (CU33).
///
/// Muestra el resumen previo (plan, número de cuota, vencimiento, importe y
/// moneda) y, solo tras una acción explícita del paciente, crea la intención
/// de Stripe y presenta el PaymentSheet de CU31.
///
/// Cerrar el PaymentSheet NO aprueba el pago: después se consulta el estado
/// real en FastAPI (`GET /pagos/stripe/pagos/{pago_id}/estado`) con reintentos
/// LIMITADOS (sin reintentos infinitos ni cobros duplicados).
class PagarCuotaPage extends StatefulWidget {
  const PagarCuotaPage({
    super.key,
    required this.plan,
    required this.cuota,
    this.planesService,
    this.stripeService,
    this.alCerrarSesion,
    this.maxVerificaciones = 5,
    this.esperaVerificacion = const Duration(seconds: 2),
  });

  /// Plan al que pertenece la cuota (datos ya consultados al backend).
  final PlanPago plan;

  /// Cuota que se va a pagar.
  final CuotaPlan cuota;

  /// Servicio de CU32/CU33; inyectable en pruebas.
  final PlanesCuotasService? planesService;

  /// Servicio de Stripe; inyectable en pruebas.
  final StripePaymentService? stripeService;

  /// Acción de cierre de sesión ante un JWT inválido o expirado.
  final Future<void> Function()? alCerrarSesion;

  /// Número máximo de consultas de estado tras el PaymentSheet.
  final int maxVerificaciones;

  /// Espera entre consultas de estado.
  final Duration esperaVerificacion;

  @override
  State<PagarCuotaPage> createState() => _PagarCuotaPageState();
}

class _PagarCuotaPageState extends State<PagarCuotaPage> {
  late final PlanesCuotasService _planesService =
      widget.planesService ?? PlanesCuotasService();
  late final StripePaymentService _stripeService =
      widget.stripeService ?? StripePaymentService();

  /// `true` mientras se prepara la intención, se presenta el PaymentSheet o se
  /// verifica el estado. Bloquea acciones repetidas (anti-doble cobro).
  bool _procesandoPago = false;

  /// Pago cuya confirmación aún no llegó (permite verificarlo de nuevo).
  int? _pagoEnVerificacion;

  @override
  void initState() {
    super.initState();
    // Un intento previo pendiente ya existente se puede verificar manualmente.
    for (final intento in widget.cuota.pagos) {
      if (intento.estado == EstadoPagoApi.pendiente && !intento.aplicadoACuota) {
        _pagoEnVerificacion = intento.pagoId;
        break;
      }
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

  /// Inicia el pago EXCLUSIVAMENTE por acción explícita del paciente.
  ///
  /// Nunca se llama desde `initState`/`build`: abrir la pantalla no crea
  /// intenciones de pago (anti-doble cobro).
  Future<void> _pagar() async {
    if (_procesandoPago) return;

    if (!_stripeService.estaConfigurado) {
      _snack('Configura la clave publicable de Stripe para pagar con tarjeta.');
      return;
    }

    setState(() {
      _procesandoPago = true;
    });

    final IntencionCuotaStripe intencion;
    try {
      intencion = await _planesService.crearIntencionCuota(widget.cuota.id);
    } on PagosException catch (error) {
      if (!mounted) return;
      setState(() {
        _procesandoPago = false;
      });

      if (error.statusCode == 401) {
        await _cerrarSesion();
        return;
      }

      // 409 = el backend rechaza el cobro (cuota ya no disponible / plan
      // inactivo / intento en curso). NO se reintenta automáticamente.
      await _dialogo(
        error.statusCode == 409 ? 'Cuota no disponible' : 'No se pudo iniciar',
        error.message,
      );
      return;
    }

    if (!mounted) return;

    final StripePagoResultado resultado;
    try {
      resultado = await _stripeService.presentar(
        clientSecret: intencion.clientSecret,
      );
    } on Exception {
      if (!mounted) return;
      setState(() {
        _procesandoPago = false;
        _pagoEnVerificacion = intencion.pagoId;
      });
      await _dialogo(
        'No se pudo abrir Stripe',
        'No se pudo presentar la pasarela de pago. '
            'Puedes verificar el estado del pago antes de reintentar.',
      );
      return;
    }

    if (!mounted) return;

    if (resultado.fueCancelado) {
      setState(() {
        _procesandoPago = false;
        _pagoEnVerificacion = intencion.pagoId;
      });
      await _dialogo(
        'Pago cancelado',
        'No se completó el pago en Stripe. La cuota sigue pendiente. '
            'Puedes verificar el estado por si el cobro quedó en proceso.',
      );
      return;
    }

    if (!resultado.fueCompletado) {
      setState(() {
        _procesandoPago = false;
        _pagoEnVerificacion = intencion.pagoId;
      });
      await _dialogo(
        'Pago no completado',
        resultado.mensaje ?? 'Stripe no completó la operación.',
      );
      return;
    }

    // PaymentSheet completado: la aprobación la decide el backend.
    _pagoEnVerificacion = intencion.pagoId;
    await _verificarPago(intencion.pagoId);
  }

  /// Verifica manualmente el pago pendiente desde el aviso en pantalla.
  Future<void> _verificarPagoPendiente() async {
    final int? pagoId = _pagoEnVerificacion;
    if (pagoId == null || _procesandoPago) return;
    await _verificarPago(pagoId);
  }

  /// Consulta el estado real del pago en el backend de forma LIMITADA.
  Future<void> _verificarPago(int pagoId) async {
    if (!mounted) return;
    setState(() {
      _procesandoPago = true;
    });

    EstadoPago? ultimoEstado;
    for (var intento = 0; intento < widget.maxVerificaciones; intento++) {
      try {
        ultimoEstado = await _planesService.consultarEstadoPago(pagoId);
      } on PagosException catch (error) {
        ultimoEstado = null;
        if (!mounted) return;
        setState(() {
          _procesandoPago = false;
        });
        await _dialogo(
          error.statusCode == 401 ? 'Sesión expirada' : 'No se pudo verificar',
          error.statusCode == 401
              ? error.message
              : 'No se pudo confirmar el estado del pago en este momento. '
                    'Puedes verificarlo nuevamente en un momento.',
        );
        if (error.statusCode == 401) await _cerrarSesion();
        return;
      }

      final EstadoPagoApi estado = ultimoEstado.estado;
      final bool terminal =
          estado.esAprobado ||
          estado == EstadoPagoApi.rechazado ||
          estado == EstadoPagoApi.anulado;
      if (terminal) break;

      if (intento < widget.maxVerificaciones - 1) {
        await Future<void>.delayed(widget.esperaVerificacion);
        if (!mounted) return;
      }
    }

    if (!mounted) return;

    final bool aprobado = ultimoEstado?.aprobado ?? false;
    setState(() {
      _procesandoPago = false;
      if (aprobado) _pagoEnVerificacion = null;
    });

    await _reportarEstado(ultimoEstado);
  }

  /// Muestra el resultado de la verificación al paciente.
  Future<void> _reportarEstado(EstadoPago? estado) async {
    if (estado == null) {
      await _dialogo(
        'No se pudo verificar',
        'No se pudo confirmar el estado del pago en este momento. '
            'Puedes verificarlo nuevamente con el botón "Verificar estado".',
      );
      return;
    }

    if (estado.aprobado) {
      await _dialogoAprobado(estado);
      return;
    }

    if (estado.estado == EstadoPagoApi.rechazado ||
        estado.estado == EstadoPagoApi.anulado) {
      await _dialogo(
        'Pago no completado',
        'El pago quedó en estado "${estado.estado.etiqueta}". '
            'La cuota sigue pendiente.',
      );
      return;
    }

    await _dialogo(
      'Pago en verificación',
      'El pago aún se está confirmando en el servidor. '
          'Puedes verificar el estado nuevamente en un momento.',
    );
  }

  /// Confirmación del pago APROBADO por el backend.
  ///
  /// Al cerrar el aviso se vuelve al detalle del plan con `true` para que
  /// recargue las cuotas desde FastAPI.
  Future<void> _dialogoAprobado(EstadoPago estado) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Pago aprobado'),
        content: Text(
          'El pago de la cuota ${widget.cuota.numeroCuota} por '
          '${formatearMontoConMoneda(estado.moneda, estado.monto)} '
          'fue confirmado en el servidor.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _dialogo(String titulo, String mensaje) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _snack(String mensaje) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final String moneda = widget.plan.moneda;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0D47A1),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pagar cuota'),
            Text(
              'Plan #${widget.plan.id} · Cuota ${widget.cuota.numeroCuota} '
              'de ${widget.plan.cantidadCuotas}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF5C6F80)),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: FondoPagos()),
          SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              children: [
                _importe(),
                const SizedBox(height: 18),
                _resumen(moneda),
                const SizedBox(height: 14),
                if (_pagoEnVerificacion != null) ...[
                  _bannerVerificacion(),
                  const SizedBox(height: 14),
                ],
                _avisoStripe(),
                const SizedBox(height: 14),
                _botonPagar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Importe exacto de la cuota, informado por el backend.
  Widget _importe() {
    return Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: const Color(0xFF1976D2).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.credit_card_outlined,
            color: Color(0xFF0D47A1),
            size: 28,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Importe a pagar',
          style: TextStyle(color: Color(0xFF5C6F80), fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          formatearMontoConMoneda(
            widget.plan.moneda,
            widget.cuota.montoProgramado,
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0D47A1),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Pago completo de la cuota ${widget.cuota.numeroCuota}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF5C6F80), fontSize: 12.5),
        ),
      ],
    );
  }

  /// Resumen previo al pago, con los datos del backend.
  Widget _resumen(String moneda) {
    return _TarjetaPago(
      children: [
        const Text(
          'Resumen de operación',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF0D47A1),
          ),
        ),
        const SizedBox(height: 12),
        _FilaResumen(
          etiqueta: 'Plan de pago',
          valor: '#${widget.plan.id}',
        ),
        _FilaResumen(
          etiqueta: 'Número de cuota',
          valor:
              '${widget.cuota.numeroCuota} / ${widget.plan.cantidadCuotas}',
        ),
        _FilaResumen(
          etiqueta: 'Vencimiento',
          valor: formatearFecha(widget.cuota.fechaVencimiento),
        ),
        const Divider(height: 22),
        _FilaResumen(
          etiqueta: 'Total a pagar',
          valor: formatearMontoConMoneda(
            moneda,
            widget.cuota.montoProgramado,
          ),
          resaltado: true,
        ),
      ],
    );
  }

  /// Aviso con opción de verificar un pago aún no confirmado.
  Widget _bannerVerificacion() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF3E5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0D7AE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.hourglass_bottom, color: Color(0xFFB26A00), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pago en verificación',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8A4B00),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Hay un intento de pago que aún no se confirma en el servidor. '
            'Puedes verificar su estado sin volver a cobrar.',
            style: TextStyle(
              color: Color(0xFF8A4B00),
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _procesandoPago ? null : _verificarPagoPendiente,
              icon: const Icon(Icons.refresh),
              label: const Text('Verificar estado'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8A4B00),
                side: const BorderSide(color: Color(0xFFE0B87A)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Nota sobre el procesamiento con Stripe y la confirmación del backend.
  Widget _avisoStripe() {
    final bool configurado = _stripeService.estaConfigurado;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: configurado ? const Color(0xFFE9F7EF) : const Color(0xFFFDF3E5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: configurado
              ? const Color(0xFFC9E9D4)
              : const Color(0xFFF0D7AE),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            configurado ? Icons.verified_user_outlined : Icons.info_outline,
            size: 18,
            color: configurado
                ? const Color(0xFF2E7D32)
                : const Color(0xFFB26A00),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              configurado
                  ? 'Tu pago se procesará mediante Stripe. La confirmación '
                        'del pago se verificará con el servidor de la clínica.'
                  : 'Pagos con tarjeta no configurados. Ejecuta la app con '
                        '--dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...',
              style: TextStyle(
                color: configurado
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF8A4B00),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Botón explícito para continuar con Stripe.
  Widget _botonPagar() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const Key('continuar-con-stripe'),
        onPressed: _procesandoPago ? null : _pagar,
        icon: _procesandoPago
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.lock_outline, size: 18),
        label: Text(
          _procesandoPago ? 'Procesando...' : 'Continuar con Stripe',
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// Contenedor blanco redondeado con la identidad visual del módulo Pagos.
class _TarjetaPago extends StatelessWidget {
  const _TarjetaPago({required this.children});

  final List<Widget> children;

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
        children: children,
      ),
    );
  }
}

/// Fila "etiqueta / valor" del resumen de operación.
class _FilaResumen extends StatelessWidget {
  const _FilaResumen({
    required this.etiqueta,
    required this.valor,
    this.resaltado = false,
  });

  final String etiqueta;
  final String valor;
  final bool resaltado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              etiqueta,
              style: TextStyle(
                color: const Color(0xFF5C6F80),
                fontSize: resaltado ? 13.5 : 12.5,
                fontWeight: resaltado ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            valor,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: resaltado ? 16 : 13,
              color: const Color(0xFF0D47A1),
            ),
          ),
        ],
      ),
    );
  }
}

