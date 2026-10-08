import 'package:flutter/material.dart';

import '../../../core/storage/token_storage.dart';
import '../../authentication_security/pages/login/login_page.dart';
import '../models/pago_models.dart';
import '../services/comprobante_archivo_service.dart';
import '../services/pagos_service.dart';
import '../services/stripe_payment_service.dart';
import '../widgets/consulta_pago_card.dart';
import '../widgets/pago_historial_card.dart';
import '../widgets/pagos_vistas.dart';
import 'comprobante_pago_page.dart';
import 'pago_detalle_page.dart';
import 'servicios_pago_page.dart';

/// Pantalla principal del módulo Pagos.
///
/// Tiene dos vistas conmutables mediante un selector:
///
/// - **Consultas:** lista las consultas clínicas del paciente con su resumen de
///   pago y permite entrar a los servicios de cada consulta para pagarlos.
/// - **Historial:** lista los pagos del paciente (más recientes primero) y
///   permite ver el detalle y el comprobante PDF de los pagos APROBADOS.
///
/// El historial se consulta SOLO al abrir su sección (operación de lectura), de
/// forma que abrir la pantalla nunca crea intenciones de pago.
class PagosPage extends StatefulWidget {
  const PagosPage({
    super.key,
    this.pagosService,
    this.stripeService,
    this.archivoService = const ComprobanteArchivoService(),
    this.visor = visorComprobantePdf,
  });

  /// Servicio HTTP de pagos; inyectable en pruebas.
  final PagosService? pagosService;

  /// Servicio de Stripe; inyectable en pruebas.
  final StripePaymentService? stripeService;

  /// Servicio de guardado/compartición del comprobante; inyectable en pruebas.
  final ComprobanteArchivoService archivoService;

  /// Constructor del visor PDF del comprobante; inyectable en pruebas.
  final VisorComprobante visor;

  @override
  State<PagosPage> createState() => _PagosPageState();
}

class _PagosPageState extends State<PagosPage> {
  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _azulPrincipal = Color(0xFF1976D2);

  late final PagosService _pagosService = widget.pagosService ?? PagosService();
  late final StripePaymentService _stripeService =
      widget.stripeService ?? StripePaymentService();

  List<ConsultaPago> _consultas = const [];
  bool _cargando = true;
  String? _error;

  /// Sección visible: 0 = Consultas, 1 = Historial.
  int _seccion = 0;

  List<PagoHistorial> _pagos = const [];
  bool _cargandoHistorial = false;
  String? _errorHistorial;

  /// `true` mientras el historial no se haya consultado en esta sesión.
  bool _historialPendiente = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Carga las consultas del paciente (una vez por apertura de la página).
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final consultas = await _pagosService.listarMisConsultas();

      if (!mounted) return;
      setState(() {
        _consultas = consultas;
        _cargando = false;
      });
    } on PagosException catch (error) {
      if (!mounted) return;

      // 401 = JWT inválido/expirado: limpiar sesión y volver al Login.
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

  /// Abre los servicios de la consulta y refresca al volver.
  Future<void> _abrirConsulta(ConsultaPago consulta) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServiciosPagoPage(
          consulta: consulta,
          pagosService: _pagosService,
          stripeService: _stripeService,
          archivoService: widget.archivoService,
          visorComprobante: widget.visor,
        ),
      ),
    );

    if (!mounted) return;
    // Refresca por si cambió el estado de pago de algún servicio y marca el
    // historial como pendiente (pudo registrarse un pago nuevo).
    setState(() {
      _historialPendiente = true;
    });
    await _cargar();
  }

  /// Carga el historial de pagos del paciente (operación de SOLO LECTURA).
  ///
  /// Se consulta al abrir la sección Historial y al volver del detalle de un
  /// pago; NUNCA al abrir la pantalla ni al pagar, por lo que no genera
  /// intenciones de pago.
  Future<void> _cargarHistorial() async {
    setState(() {
      _cargandoHistorial = true;
      _errorHistorial = null;
    });

    try {
      final pagos = await _pagosService.listarMisPagos();

      if (!mounted) return;
      setState(() {
        _pagos = pagos;
        _cargandoHistorial = false;
        _historialPendiente = false;
      });
    } on PagosException catch (error) {
      if (!mounted) return;

      // 401 = JWT inválido/expirado: limpiar sesión y volver al Login.
      if (error.statusCode == 401) {
        await _cerrarSesion();
        return;
      }

      setState(() {
        _errorHistorial = error.message;
        _cargandoHistorial = false;
      });
    }
  }

  /// Cambia de sección cargando el historial solo cuando hace falta.
  void _cambiarSeccion(int seccion) {
    setState(() {
      _seccion = seccion;
    });

    if (seccion == 1 && _historialPendiente && !_cargandoHistorial) {
      _cargarHistorial();
    }
  }

  /// Abre el detalle de un pago; al volver refresca el historial.
  Future<void> _abrirPago(PagoHistorial pago) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PagoDetallePage(
          pago: pago,
          pagosService: _pagosService,
          archivoService: widget.archivoService,
          visor: widget.visor,
        ),
      ),
    );

    if (!mounted) return;
    await _cargarHistorial();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: FondoPagos()),
          SafeArea(
            child: RefreshIndicator(
              color: _azulPrincipal,
              onRefresh: _seccion == 0 ? _cargar : _cargarHistorial,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  _encabezado(),
                  const SizedBox(height: 16),
                  _selector(),
                  const SizedBox(height: 16),
                  if (_seccion == 0) ...[
                    if (!_stripeService.estaConfigurado) ...[
                      _avisoStripe(),
                      const SizedBox(height: 16),
                    ],
                    _contenido(),
                  ] else
                    _contenidoHistorial(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Selector entre las dos vistas del módulo: Consultas e Historial.
  Widget _selector() {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment<int>(
          value: 0,
          label: Text('Consultas'),
          icon: Icon(Icons.list_alt_outlined),
        ),
        ButtonSegment<int>(
          value: 1,
          label: Text('Historial'),
          icon: Icon(Icons.receipt_long_outlined),
        ),
      ],
      selected: {_seccion},
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF5C6F80),
        selectedBackgroundColor: const Color(0xFFD8ECFA),
        selectedForegroundColor: _azulProfundo,
        side: const BorderSide(color: Color(0xFFCDE3F5)),
      ),
      onSelectionChanged: (seleccion) => _cambiarSeccion(seleccion.first),
    );
  }

  /// Historial de pagos: carga, error, vacío o lista de pagos.
  Widget _contenidoHistorial() {
    if (_cargandoHistorial) {
      return const PagosCargando(mensaje: 'Cargando tu historial de pagos...');
    }

    if (_errorHistorial != null) {
      return PagosErrorVista(
        titulo: 'No se pudo cargar tu historial',
        mensaje: _errorHistorial!,
        onReintentar: _cargarHistorial,
      );
    }

    if (_pagos.isEmpty) {
      return const PagosVacioVista(
        icono: Icons.receipt_long_outlined,
        mensaje: 'Aún no tienes pagos registrados en tu historial.',
      );
    }

    return Column(
      children: [
        for (final pago in _pagos)
          PagoHistorialCard(pago: pago, onTap: () => _abrirPago(pago)),
      ],
    );
  }

  Widget _encabezado() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _azulPrincipal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.payments_outlined, color: _azulProfundo),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Pagos',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0D47A1),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Consulta y paga los servicios de tus atenciones de forma segura.',
          style: TextStyle(color: Color(0xFF5C6F80), height: 1.4),
        ),
      ],
    );
  }

  /// Aviso cuando falta la publishable key de Stripe.
  Widget _avisoStripe() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF3E5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0D7AE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFB26A00)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pagos con tarjeta no configurados',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8A4B00),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Para habilitar el PaymentSheet de Stripe, ejecuta la app '
                  'con tu clave publicable de prueba (pk_test_...):\n'
                  'flutter run --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...',
                  style: TextStyle(
                    color: Color(0xFF8A4B00),
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenido() {
    if (_cargando) {
      return const PagosCargando(mensaje: 'Cargando tus consultas...');
    }

    if (_error != null) {
      return PagosErrorVista(
        titulo: 'No se pudieron cargar tus pagos',
        mensaje: _error!,
        onReintentar: _cargar,
      );
    }

    if (_consultas.isEmpty) {
      return const PagosVacioVista(
        icono: Icons.receipt_long_outlined,
        mensaje: 'No tienes consultas con información de pago por el momento.',
      );
    }

    return Column(
      children: [
        for (final consulta in _consultas)
          ConsultaPagoCard(
            consulta: consulta,
            onTap: () => _abrirConsulta(consulta),
          ),
      ],
    );
  }
}
