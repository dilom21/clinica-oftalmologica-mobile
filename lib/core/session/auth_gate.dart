import 'package:flutter/material.dart';

import '../storage/token_storage.dart';
import '../../features/authentication_security/pages/login/login_page.dart';
import '../../features/home/pages/main_navigation_page.dart';
import '../../features/notificaciones/services/push_runtime.dart';
import '../../features/perfil_paciente/services/paciente_service.dart';

enum _EstadoAuthGate { verificando, sinSesion, autenticado, error }

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    this.onSessionResolved,
    this.readToken,
    this.readEmpresaCodigo,
    this.validatePatient,
    this.revokePush,
    this.deleteSession,
    this.authenticatedBuilder,
  });

  final ValueChanged<bool>? onSessionResolved;

  // Dependencias sustituibles para pruebas.
  final Future<String?> Function()? readToken;
  final Future<String?> Function()? readEmpresaCodigo;
  final Future<void> Function()? validatePatient;
  final Future<void> Function()? revokePush;
  final Future<void> Function()? deleteSession;
  final WidgetBuilder? authenticatedBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final TokenStorage _storage = TokenStorage();
  final PacienteService _pacienteService = PacienteService();

  _EstadoAuthGate _estado = _EstadoAuthGate.verificando;

  String _mensaje = 'Estamos verificando tu sesión.';
  bool _restaurando = false;

  @override
  void initState() {
    super.initState();
    _restaurarSesion();
  }

  Future<void> _restaurarSesion() async {
    if (_restaurando) return;

    _restaurando = true;

    if (mounted) {
      setState(() {
        _estado = _EstadoAuthGate.verificando;
        _mensaje = 'Estamos verificando tu sesión.';
      });
    }

    try {
      // 1. Recuperar JWT almacenado de forma segura.
      final String? token =
          await (widget.readToken?.call() ?? _storage.getToken());

      if (token == null || token.trim().isEmpty) {
        _mostrarLogin();
        return;
      }

      // 2. Recuperar la clínica asociada al JWT.
      final String? empresaCodigo =
          await (widget.readEmpresaCodigo?.call() ??
              _storage.getEmpresaCodigo());

      // Una sesión tenant sin código de clínica está incompleta.
      if (empresaCodigo == null || empresaCodigo.trim().isEmpty) {
        await (widget.deleteSession?.call() ?? _storage.deleteSession());
        _mostrarLogin();
        return;
      }

      // 3. Validar la sesión contra el backend real.
      // GET /pacientes/me con Authorization: Bearer <JWT>.
      await (widget.validatePatient?.call() ??
          _pacienteService.obtenerMiPerfil());

      if (!mounted) return;

      setState(() {
        _estado = _EstadoAuthGate.autenticado;
      });

      _notificarSesionResuelta(true);
    } on PacienteException catch (error) {
      if (error.statusCode == 401) {
        // El servidor rechazó el JWT.
        // Intentamos revocar el dispositivo antes de borrar la sesión.
        try {
          await (widget.revokePush?.call() ??
              PushRuntime.coordinator.revokeBeforeLogout());
        } catch (_) {
          // La revocación no debe impedir limpiar una sesión inválida.
        }

        try {
          await (widget.deleteSession?.call() ?? _storage.deleteSession());
        } catch (_) {
          _mostrarError('No se pudo limpiar la sesión. Inténtalo nuevamente.');
          return;
        }

        _mostrarLogin();
        return;
      }

      // Errores de conexión, permisos, servidor o perfil:
      // conservar el JWT y permitir reintentar.
      _mostrarError(error.message);
    } catch (_) {
      // No borrar la sesión ante errores que no confirman
      // que el JWT sea inválido.
      _mostrarError(
        'No se pudo verificar tu sesión. '
        'Comprueba tu conexión e inténtalo nuevamente.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _restaurando = false;
        });
      } else {
        _restaurando = false;
      }
    }
  }

  void _mostrarLogin() {
    if (!mounted) return;

    setState(() {
      _estado = _EstadoAuthGate.sinSesion;
    });

    _notificarSesionResuelta(false);
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;

    setState(() {
      _estado = _EstadoAuthGate.error;
      _mensaje = mensaje;
    });

    // No notificar una sesión inválida.
    // Un error de conexión no significa que el JWT haya expirado.
    // La notificación pendiente se conserva hasta reintentar.
  }

  void _notificarSesionResuelta(bool autenticada) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onSessionResolved?.call(autenticada);
    });
  }

  Future<void> _cerrarSesion() async {
    try {
      await (widget.revokePush?.call() ??
          PushRuntime.coordinator.revokeBeforeLogout());
    } catch (_) {
      // Se continúa con el cierre local.
    }

    try {
      await (widget.deleteSession?.call() ?? _storage.deleteSession());
    } catch (_) {
      _mostrarError('No se pudo cerrar la sesión. Inténtalo nuevamente.');
      return;
    }

    _mostrarLogin();
  }

  @override
  Widget build(BuildContext context) {
    switch (_estado) {
      case _EstadoAuthGate.verificando:
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(_mensaje),
              ],
            ),
          ),
        );

      case _EstadoAuthGate.sinSesion:
        return const LoginPage();

      case _EstadoAuthGate.autenticado:
        return widget.authenticatedBuilder?.call(context) ??
            const MainNavigationPage();

      case _EstadoAuthGate.error:
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 64,
                      color: Colors.blueGrey,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'No se pudo verificar tu sesión',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(_mensaje, textAlign: TextAlign.center),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _restaurando ? null : _restaurarSesion,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ),
                    TextButton(
                      onPressed: _restaurando ? null : _cerrarSesion,
                      child: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    }
  }
}
