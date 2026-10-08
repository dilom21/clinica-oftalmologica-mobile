import 'package:flutter/material.dart';

import '../../../core/storage/token_storage.dart';
import '../../authentication_security/pages/login/login_page.dart';
import '../models/pago_models.dart';
import '../services/comprobante_archivo_service.dart';
import '../services/pagos_service.dart';
import '../services/stripe_payment_service.dart';
import '../widgets/pago_resumen_bar.dart';
import '../widgets/pagos_vistas.dart';
import '../widgets/servicio_pago_tile.dart';
import 'comprobante_pago_page.dart';

/// Pantalla de servicios realizados de una consulta clínica.
///
/// Permite seleccionar uno, varios o todos los servicios PENDIENTES de ESTA
/// consulta, ver el total en vivo y pagarlos con tarjeta vía Stripe
/// PaymentSheet. Los servicios PAGADOS no pueden volver a seleccionarse y no
/// se pueden mezclar servicios de consultas distintas (solo se listan los de
/// la consulta abierta).
///
/// El backend es la única fuente de verdad: tras el PaymentSheet se consulta
/// el estado real del pago (con reintentos LIMITADOS).
class ServiciosPagoPage extends StatefulWidget {
  const ServiciosPagoPage({
    super.key,
    required this.consulta,
    this.pagosService,
    this.stripeService,
    this.archivoService = const ComprobanteArchivoService(),
    this.visorComprobante = visorComprobantePdf,
    this.maxVerificaciones = 5,
    this.esperaVerificacion = const Duration(seconds: 2),
  });

  /// Consulta cuyos servicios se van a mostrar.
  final ConsultaPago consulta;

  /// Servicio HTTP de pagos; inyectable en pruebas.
  final PagosService? pagosService;

  /// Servicio de Stripe; inyectable en pruebas.
  final StripePaymentService? stripeService;

  /// Servicio de guardado/compartición del comprobante; inyectable en pruebas.
  final ComprobanteArchivoService archivoService;

  /// Constructor del visor PDF del comprobante; inyectable en pruebas.
  final VisorComprobante visorComprobante;

  /// Número máximo de consultas de estado tras un intento de pago.
  final int maxVerificaciones;

  /// Espera entre consultas de estado.
  final Duration esperaVerificacion;

  @override
  State<ServiciosPagoPage> createState() => _ServiciosPagoPageState();
}

class _ServiciosPagoPageState extends State<ServiciosPagoPage> {
  late final PagosService _pagosService = widget.pagosService ?? PagosService();
  late final StripePaymentService _stripeService =
      widget.stripeService ?? StripePaymentService();

  List<ServicioRealizadoPago> _servicios = const [];
  final Set<int> _seleccionados = <int>{};

  bool _cargando = true;
  String? _error;

  /// `true` mientras se prepara la intención, se presenta el PaymentSheet o se
  /// verifica el estado. Bloquea acciones repetidas (anti-doble cobro).
  bool _procesandoPago = false;

  /// Pago cuya confirmación aún no llegó (permite verificarlo de nuevo).
  int? _pagoEnVerificacion;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Carga los servicios de la consulta (una vez por apertura de la página).
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final servicios = await _pagosService.listarServiciosDeConsulta(
        widget.consulta.consultaId,
      );

      if (!mounted) return;
      setState(() {
        _servicios = servicios;
        _cargando = false;
        // Descarta de la selección lo que ya no sea seleccionable.
        final validos = idsSeleccionables(servicios);
        _seleccionados.removeWhere((id) => !validos.contains(id));
      });
    } on PagosException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) {
        await _cerrarSesion();
        return;
      }
      setState(() {
        _error = error.message;
        _cargando = false;
      });
    }
  }

  Future<void> _cerrarSesion() async {
    await TokenStorage().deleteToken();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  // ---------------------------------------------------------------
  // Selección y total
  // ---------------------------------------------------------------

  /// Ids de todos los servicios seleccionables (pendientes con precio).
  Set<int> get _pendientes => idsSeleccionables(_servicios);

  /// Total de la selección actual (solo servicios cobrables).
  double get _total => totalSeleccionado(_servicios, _seleccionados);

  /// El pago solo puede iniciarse tras una acción explícita y con selección.
  bool get _puedePagar => _seleccionados.isNotEmpty && !_procesandoPago;

  void _alternar(int id, bool valor) {
    setState(() {
      if (valor) {
        _seleccionados.add(id);
      } else {
        _seleccionados.remove(id);
      }
    });
  }

  void _seleccionarTodosPendientes() {
    setState(() {
      _seleccionados
        ..clear()
        ..addAll(_pendientes);
    });
  }

  void _limpiarSeleccion() => setState(_seleccionados.clear);

  // ---------------------------------------------------------------
  // Pago
  // ---------------------------------------------------------------

  /// Inicia el pago EXCLUSIVAMENTE por acción explícita del usuario.
  ///
  /// Nunca se llama desde `initState`/`build`, evitando crear intenciones al
  /// reconstruir widgets (anti-doble cobro).
  Future<void> _pagar() async {
    if (!_puedePagar) return;

    if (!_stripeService.estaConfigurado) {
      _snack('Configura la clave publicable de Stripe para pagar con tarjeta.');
      return;
    }

    setState(() {
      _procesandoPago = true;
    });

    final List<int> ids = _seleccionados.toList()..sort();

    final PagoIntencion intencion;
    try {
      intencion = await _pagosService.crearIntencion(ids);
    } on PagosException catch (error) {
      if (!mounted) return;
      setState(() {
        _procesandoPago = false;
      });

      // HTTP 409 = protección anti-doble cobro del backend.
      // NO se genera otra intención automáticamente.
      if (error.statusCode == 409) {
        await _dialogo(
          'Pago en curso',
          '${error.message}\n\nActualiza el estado de tus servicios antes de '
              'intentarlo de nuevo.',
        );
        await _cargar();
        return;
      }

      _snack(error.message);
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
      _snack('No se pudo abrir el pago con tarjeta.');
      return;
    }

    if (!mounted) return;

    // Cancelación voluntaria: NO se inventa un estado definitivo.
    if (resultado.fueCancelado) {
      setState(() {
        _procesandoPago = false;
        _pagoEnVerificacion = intencion.pagoId;
      });
      await _dialogo(
        'Pago cancelado',
        'Cancelaste el proceso de pago. Si ya habías autorizado un cobro, '
            'puedes verificar su estado.',
      );
      return;
    }

    if (resultado.resultado == ResultadoPaymentSheet.error) {
      setState(() {
        _procesandoPago = false;
        _pagoEnVerificacion = intencion.pagoId;
      });
      _snack(resultado.mensaje ?? 'No se pudo completar el pago.');
      return;
    }

    // PaymentSheet completado: se confirma el estado REAL con el backend.
    setState(() {
      _pagoEnVerificacion = intencion.pagoId;
    });
    await _verificarPago(intencion.pagoId);
  }

  /// Vuelve a verificar el pago pendiente pendiente de confirmación.
  Future<void> _verificarPagoPendiente() async {
    final pagoId = _pagoEnVerificacion;
    if (pagoId == null || _procesandoPago) return;
    await _verificarPago(pagoId);
  }

  /// Consulta el estado real del pago en el backend de forma LIMITADA.
  ///
  /// El backend es la única fuente de verdad. NUNCA se marca el pago como
  /// aprobado sin su confirmación y no hay reintentos infinitos.
  Future<void> _verificarPago(int pagoId) async {
    setState(() {
      _procesandoPago = true;
    });

    EstadoPago? ultimoEstado;
    for (var intento = 0; intento < widget.maxVerificaciones; intento++) {
      try {
        ultimoEstado = await _pagosService.consultarEstado(pagoId);
      } on PagosException {
        ultimoEstado = null;
        break; // error de red/servidor: se reporta abajo.
      }

      final estado = ultimoEstado.estado;
      final terminal =
          estado.esAprobado ||
          estado == EstadoPagoApi.rechazado ||
          estado == EstadoPagoApi.anulado;
      if (terminal) break;

      // PENDIENTE (u otro no terminal): esperar y reintentar (limitado).
      if (intento < widget.maxVerificaciones - 1) {
        await Future<void>.delayed(widget.esperaVerificacion);
        if (!mounted) return;
      }
    }

    if (!mounted) return;

    final aprobado = ultimoEstado?.aprobado ?? false;
    setState(() {
      _procesandoPago = false;
      if (aprobado) {
        _seleccionados.clear();
        _pagoEnVerificacion = null;
      }
    });

    await _reportarEstado(ultimoEstado);
    await _cargar();
  }

  /// Muestra el resultado de la verificación al paciente.
  Future<void> _reportarEstado(EstadoPago? estado) async {
    if (estado == null) {
      await _dialogo(
        'No se pudo verificar',
        'No se pudo confirmar el estado del pago en este momento. '
            'Puedes verificar nuevamente con el botón "Verificar estado".',
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
            'Los servicios siguen pendientes.',
      );
      return;
    }

    await _dialogo(
      'Pago en verificación',
      'El pago aún se está confirmando en el servidor. '
          'Puedes verificar el estado nuevamente en un momento.',
    );
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

  /// Confirmación del pago APROBADO con acceso inmediato al comprobante.
  ///
  /// El botón "Ver comprobante" solo aparece cuando el backend ya confirmó el
  /// estado APROBADO y usa el `pago_id` del pago recién verificado, por lo que
  /// no es necesario pasar por el historial.
  Future<void> _dialogoAprobado(EstadoPago estado) async {
    final String? accion = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pago aprobado'),
        content: Text(
          'Pago realizado correctamente.\n'
          'Tu pago por Bs ${formatearMonto(estado.monto)} fue confirmado '
          'en el servidor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop('comprobante'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Ver comprobante'),
          ),
        ],
      ),
    );

    if (!mounted || accion != 'comprobante') return;

    await _abrirComprobante(estado.pagoId);
  }

  /// Abre la pantalla dedicada del comprobante del pago confirmado.
  Future<void> _abrirComprobante(int pagoId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComprobantePagoPage(
          pagoId: pagoId,
          pagosService: _pagosService,
          archivoService: widget.archivoService,
          visor: widget.visorComprobante,
        ),
      ),
    );
  }

  void _snack(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // ---------------------------------------------------------------
  // Interfaz
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final mostrarBarra = !_cargando && _error == null && _servicios.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0D47A1),
        elevation: 0,
        title: const Text('Servicios de la consulta'),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: FondoPagos()),
          SafeArea(top: false, child: _cuerpo()),
        ],
      ),
      bottomNavigationBar: mostrarBarra
          ? PagoResumenBar(
              total: _total,
              habilitado: _seleccionados.isNotEmpty,
              procesando: _procesandoPago,
              onPagar: _pagar,
            )
          : null,
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: PagosCargando(mensaje: 'Cargando servicios...'),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: PagosErrorVista(
          titulo: 'No se pudieron cargar los servicios',
          mensaje: _error!,
          onReintentar: _cargar,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      children: [
        _tarjetaConsulta(),
        const SizedBox(height: 16),
        if (_pagoEnVerificacion != null) ...[
          _bannerVerificacion(),
          const SizedBox(height: 16),
        ],
        if (_servicios.isEmpty)
          const PagosVacioVista(
            icono: Icons.medical_information_outlined,
            mensaje: 'Esta consulta no tiene servicios registrados.',
          )
        else ...[
          _accionesSeleccion(),
          const SizedBox(height: 10),
          for (final servicio in _servicios)
            ServicioPagoTile(
              servicio: servicio,
              seleccionado: _seleccionados.contains(
                servicio.servicioRealizadoId,
              ),
              onChanged: (valor) =>
                  _alternar(servicio.servicioRealizadoId, valor),
            ),
        ],
      ],
    );
  }

  /// Tarjeta con la información de la consulta abierta.
  Widget _tarjetaConsulta() {
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
        children: [
          Row(
            children: [
              const Icon(
                Icons.event_note_outlined,
                size: 20,
                color: Color(0xFF1976D2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Consulta del ${formatearFecha(widget.consulta.fechaConsulta)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1),
                  ),
                ),
              ),
            ],
          ),
          if (widget.consulta.oftalmologo != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.consulta.oftalmologo!,
              style: const TextStyle(color: Color(0xFF5C6F80), fontSize: 13),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'Selecciona los servicios pendientes que deseas pagar. '
            'Los servicios ya pagados no pueden volver a seleccionarse.',
            style: TextStyle(
              color: Color(0xFF8A9BA9),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Aviso con opción de verificar un pago aún no confirmado.
  Widget _bannerVerificacion() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF3E5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0D7AE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_bottom, color: Color(0xFFB26A00)),
              const SizedBox(width: 10),
              const Expanded(
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
          const SizedBox(height: 8),
          const Text(
            'Hay un pago que aún no se ha confirmado en el servidor. '
            'Puedes verificar su estado.',
            style: TextStyle(
              color: Color(0xFF8A4B00),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
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

  /// Encabezado con acciones de selección y conteo de pendientes.
  Widget _accionesSeleccion() {
    final pendientes = _pendientes.length;
    final todosSeleccionados =
        pendientes > 0 && _seleccionados.length == pendientes;

    return Row(
      children: [
        const Icon(Icons.checklist_rtl, size: 18, color: Color(0xFF5C6F80)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            pendientes == 0
                ? 'No hay servicios pendientes'
                : '$pendientes servicio(s) pendiente(s)',
            style: const TextStyle(color: Color(0xFF5C6F80), fontSize: 13),
          ),
        ),
        if (pendientes > 0)
          TextButton(
            onPressed: _procesandoPago
                ? null
                : (todosSeleccionados
                      ? _limpiarSeleccion
                      : _seleccionarTodosPendientes),
            child: Text(todosSeleccionados ? 'Limpiar' : 'Seleccionar todos'),
          ),
      ],
    );
  }
}
