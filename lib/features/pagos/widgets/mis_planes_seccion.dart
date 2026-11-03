import 'package:flutter/material.dart';

import '../../../core/storage/token_storage.dart';
import '../../authentication_security/pages/login/login_page.dart';
import '../models/planes_cuotas_models.dart';
import '../pages/plan_detalle_page.dart';
import '../services/pagos_service.dart';
import '../services/planes_cuotas_service.dart';
import '../services/stripe_payment_service.dart';
import 'pagos_vistas.dart';
import 'plan_pago_card.dart';

/// Sección "Planes y cuotas" del módulo Pagos (CU32).
///
/// Lista los planes del paciente autenticado con su estado, montos, avance y
/// aviso de cuotas vencidas, y permite abrir el detalle de cada plan.
///
/// Solo consulta datos (`GET /pagos/mis-planes`): nunca crea intenciones de
/// pago. El estado es público para que el contenedor de pestañas pueda pedir
/// una actualización al volver a mostrarse.
class MisPlanesSeccion extends StatefulWidget {
  const MisPlanesSeccion({
    super.key,
    this.planesService,
    this.stripeService,
    this.alCerrarSesion,
  });

  /// Servicio de CU32/CU33; inyectable en pruebas.
  final PlanesCuotasService? planesService;

  /// Servicio de Stripe; se propaga al detalle y al pago de cuotas.
  final StripePaymentService? stripeService;

  /// Acción de cierre de sesión ante un JWT inválido o expirado.
  final Future<void> Function()? alCerrarSesion;

  @override
  State<MisPlanesSeccion> createState() => MisPlanesSeccionState();
}

/// Estado de [MisPlanesSeccion].
class MisPlanesSeccionState extends State<MisPlanesSeccion> {
  static const Color _azulProfundo = Color(0xFF0D47A1);

  /// Ventana de frescura: dentro de este intervalo no se repite la consulta.
  static const Duration _vigenciaDatos = Duration(seconds: 15);

  late final PlanesCuotasService _planesService =
      widget.planesService ?? PlanesCuotasService();
  late final StripePaymentService _stripeService =
      widget.stripeService ?? StripePaymentService();

  List<PlanPagoResumen> _planes = const [];
  bool _cargando = true;
  String? _error;

  /// Petición en curso (evita solicitudes simultáneas).
  bool _enCurso = false;

  /// Momento de la última carga correcta.
  DateTime? _actualizadoEn;

  /// `true` cuando pudo registrarse un pago y conviene refrescar.
  bool _pendiente = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Indica si la última carga está vencida (o no existe).
  bool get _datosVencidos {
    if (_actualizadoEn == null) return true;
    return DateTime.now().difference(_actualizadoEn!) >= _vigenciaDatos;
  }

  /// Pide actualizar los planes cuando el paciente vuelve a la sección.
  Future<void> alMostrar() async {
    if (!_pendiente && !_datosVencidos) return;
    await _cargar(silencioso: _planes.isNotEmpty);
  }

  /// Refresco manual (deslizar hacia abajo en la sección Pagos).
  Future<void> refrescar() => _cargar(silencioso: _planes.isNotEmpty);

  /// Carga los planes del paciente (operación de SOLO LECTURA).
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
      final List<PlanPagoResumen> planes = await _planesService
          .listarMisPlanes();

      if (!mounted) return;
      setState(() {
        _planes = planes;
        _cargando = false;
        _error = null;
        _pendiente = false;
        _actualizadoEn = DateTime.now();
      });
    } on PagosException catch (error) {
      if (!mounted) return;

      // 401 = JWT inválido/expirado: limpiar la sesión y volver al Login.
      if (error.statusCode == 401) {
        await _cerrarSesion();
        return;
      }

      setState(() {
        _cargando = false;
        if (!silencioso || _planes.isEmpty) {
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

  /// Abre el detalle del plan y refresca al volver.
  Future<void> _abrirPlan(PlanPagoResumen plan) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanDetallePage(
          planId: plan.id,
          planesService: _planesService,
          stripeService: _stripeService,
          alCerrarSesion: widget.alCerrarSesion,
        ),
      ),
    );

    if (!mounted) return;
    _pendiente = true;
    await _cargar(silencioso: _planes.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mis planes de pago',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _azulProfundo,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Consulta tus planes activos y el estado de sus cuotas.',
          style: TextStyle(color: Color(0xFF5C6F80), height: 1.4),
        ),
        const SizedBox(height: 16),
        _contenido(),
      ],
    );
  }

  /// Carga, error, lista vacía o tarjetas de planes.
  Widget _contenido() {
    if (_cargando) {
      return const PagosCargando(mensaje: 'Cargando tus planes de pago...');
    }

    if (_error != null) {
      return PagosErrorVista(
        titulo: 'No se pudieron cargar tus planes',
        mensaje: _error!,
        onReintentar: _cargar,
      );
    }

    if (_planes.isEmpty) {
      return const PagosVacioVista(
        icono: Icons.event_note_outlined,
        mensaje: 'No tienes planes de pago registrados por el momento.',
      );
    }

    return Column(
      children: [
        for (final plan in _planes)
          PlanPagoCard(plan: plan, onTap: () => _abrirPlan(plan)),
      ],
    );
  }
}

