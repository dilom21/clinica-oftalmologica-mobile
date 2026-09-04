import 'package:flutter/material.dart';

import '../inicio/inicio_page.dart';
import '../citas/citas_page.dart';
import '../perfil/perfil_page.dart';

/// Contenedor principal del área autenticada (pacientes).
///
/// Responsabilidades:
/// - mantener UNA sola NavigationBar inferior (Material 3)
/// - manejar el índice seleccionado
/// - alternar entre Inicio, Citas y Perfil sin recrear las páginas
///   (IndexedStack conserva su estado y evita peticiones innecesarias).
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;

  // Construidas una sola vez: cada tab conserva su estado al navegar.
  static const List<Widget> _pages = [
    InicioPage(),
    CitasPage(),
    PerfilPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
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
            iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
              (states) {
                final seleccionado = states.contains(WidgetState.selected);
                return IconThemeData(
                  color: seleccionado
                      ? const Color(0xFF1976D2)
                      : const Color(0xFF8A9BA9),
                );
              },
            ),
            labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
              (states) {
                final seleccionado = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: 12,
                  fontWeight: seleccionado
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: seleccionado
                      ? const Color(0xFF0D47A1)
                      : const Color(0xFF6B7C8C),
                );
              },
            ),
          ),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
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
