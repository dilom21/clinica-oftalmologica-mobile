import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import 'inicio_page.dart';
import '../../citas/pages/citas_page.dart';
import '../../pagos/pages/pagos_page.dart';
import '../../pagos/services/pagos_service.dart';
import '../../pagos/services/stripe_payment_service.dart';
import '../../perfil_paciente/pages/perfil_page.dart';

/// Contenedor principal del área autenticada (pacientes).
///
/// Responsabilidades:
/// - mantener UNA sola NavigationBar inferior (Material 3)
/// - manejar el índice seleccionado
/// - alternar entre Inicio, Citas, Pagos y Perfil sin recrear las páginas
///   (IndexedStack conserva su estado y evita peticiones innecesarias).
/// - pedir a la pestaña Pagos que actualice sus datos al volver a mostrarse:
///   un pago registrado en recepción debe verse sin reiniciar la app.
/// - exponer la clínica de la sesión ([SesionClinica]) a Inicio y Perfil, para
///   que la identidad mostrada sea la de la clínica autenticada y no una fija.
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({
    super.key,
    this.pagosService,
    this.stripeService,
    this.sesionClinica,
  });

  /// Servicio de pagos; inyectable en pruebas.
  final PagosService? pagosService;

  /// Servicio de Stripe; inyectable en pruebas.
  final StripePaymentService? stripeService;

  /// Clínica de la sesión activa; inyectable en pruebas.
  ///
  /// Si no se provee, la página crea una y la carga desde el almacenamiento
  /// seguro, donde el login guardó el código y el nombre reales de la clínica.
  final SesionClinica? sesionClinica;

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;

  /// Permite pedir a Pagos que refresque sus datos al volver a su pestaña.
  ///
  /// `IndexedStack` conserva el estado de cada pestaña y no vuelve a ejecutar
  /// `initState`, por eso el refresco se pide explícitamente desde aquí.
  final GlobalKey<PagosPageState> _pagosKey = GlobalKey<PagosPageState>();

  /// Clínica de la sesión activa (solo lectura para la interfaz).
  late final SesionClinica _sesionClinica =
      widget.sesionClinica ?? SesionClinica();

  @override
  void initState() {
    super.initState();
    // La sesión se lee UNA vez, fuera de `build()`, y solo si aún no se cargó.
    if (!_sesionClinica.cargada) {
      _sesionClinica.cargar();
    }
  }

  @override
  void dispose() {
    if (widget.sesionClinica == null) {
      _sesionClinica.dispose();
    }
    super.dispose();
  }

  /// Cambia de pestaña y actualiza Pagos cuando vuelve a mostrarse.
  void _seleccionar(int index) {
    if (index == _selectedIndex) return;

    setState(() {
      _selectedIndex = index;
    });

    if (index == 2) {
      // Solo lectura (consultas/historial): nunca crea una intención de pago.
      _pagosKey.currentState?.alMostrarPestana();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Se reconstruye solo cuando cambia la clínica de la sesión; el estado de
      // cada pestaña se conserva porque los tipos y las claves no cambian.
      body: AnimatedBuilder(
        animation: _sesionClinica,
        builder: (context, _) => IndexedStack(
          index: _selectedIndex,
          children: <Widget>[
            InicioPage(clinica: _sesionClinica.clinica),
            const CitasPage(),
            PagosPage(
              key: _pagosKey,
              pagosService: widget.pagosService,
              stripeService: widget.stripeService,
            ),
            PerfilPage(
              clinica: _sesionClinica.clinica,
              alCerrarSesion: _sesionClinica.limpiar,
            ),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0D47A1).withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFD8ECFA),
            elevation: 0,
            iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((
              states,
            ) {
              final seleccionado = states.contains(WidgetState.selected);
              return IconThemeData(
                color: seleccionado
                    ? const Color(0xFF1976D2)
                    : const Color(0xFF8A9BA9),
              );
            }),
            labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((
              states,
            ) {
              final seleccionado = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 12,
                fontWeight: seleccionado ? FontWeight.w600 : FontWeight.w500,
                color: seleccionado
                    ? const Color(0xFF0D47A1)
                    : const Color(0xFF6B7C8C),
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _seleccionar,
            height: 68,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Citas',
              ),
              NavigationDestination(
                icon: Icon(Icons.payments_outlined),
                selectedIcon: Icon(Icons.payments),
                label: 'Pagos',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Perfil',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
