import 'package:flutter/material.dart';

import 'inicio_page.dart';
import '../../citas/pages/citas_page.dart';
import '../../pagos/pages/pagos_page.dart';
import '../../perfil_paciente/pages/perfil_page.dart';
import '../../valoraciones/pages/valoraciones_page.dart';

/// Contenedor principal del área autenticada (pacientes).
///
/// Responsabilidades:
/// - mantener UNA sola NavigationBar inferior (Material 3)
/// - manejar el índice seleccionado
/// - alternar entre Inicio, Citas, Pagos, Valoraciones y Perfil sin recrear
///   las páginas (IndexedStack conserva su estado).
/// - mostrar un indicador (badge) en Valoraciones cuando existen atenciones
///   pendientes por calificar (CU40).
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;
  int _pendientesValoracion = 0;

  void _actualizarPendientes(int cantidad) {
    if (!mounted || _pendientesValoracion == cantidad) return;
    setState(() {
      _pendientesValoracion = cantidad;
    });
  }

  void _irAValoraciones() {
    if (!mounted) return;
    setState(() {
      _selectedIndex = 3;
    });
  }

  late final List<Widget> _pages = [
    InicioPage(
      onAbrirValoraciones: _irAValoraciones,
      onPendientesActualizados: _actualizarPendientes,
    ),
    const CitasPage(),
    const PagosPage(),
    ValoracionesPage(onPendientesActualizados: _actualizarPendientes),
    const PerfilPage(),
  ];

  Widget _iconoValoraciones({required bool seleccionado}) {
    final icono = Icon(seleccionado ? Icons.star : Icons.star_outline);
    if (_pendientesValoracion <= 0) {
      return icono;
    }
    return Badge.count(count: _pendientesValoracion, child: icono);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
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
                fontSize: 11.5,
                fontWeight: seleccionado ? FontWeight.w600 : FontWeight.w500,
                color: seleccionado
                    ? const Color(0xFF0D47A1)
                    : const Color(0xFF6B7C8C),
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            height: 68,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Inicio',
              ),
              const NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Citas',
              ),
              const NavigationDestination(
                icon: Icon(Icons.payments_outlined),
                selectedIcon: Icon(Icons.payments),
                label: 'Pagos',
              ),
              NavigationDestination(
                icon: _iconoValoraciones(seleccionado: false),
                selectedIcon: _iconoValoraciones(seleccionado: true),
                label: 'Valorar',
              ),
              const NavigationDestination(
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
