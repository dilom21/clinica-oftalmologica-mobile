import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'core/config/stripe_config.dart';
import 'core/session/auth_gate.dart';
import 'core/storage/token_storage.dart';
import 'features/citas/pages/cita_detalle_page.dart';
import 'features/notificaciones/services/push_runtime.dart';
import 'features/notificaciones/services/push_transport.dart';
import 'features/notificaciones/services/local_push_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa Stripe solo si existe una clave publicable configurada.
  if (StripeConfig.estaConfigurada) {
    try {
      Stripe.publishableKey = StripeConfig.publishableKey.trim();
      await Stripe.instance.applySettings();
    } on Exception {
      // Pagos informará al paciente si Stripe no está disponible.
    }
  }

  // Inicialización de Firebase y transporte de notificaciones.
  await PushRuntime.initialize();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  StreamSubscription<int>? _openSubscription;
  StreamSubscription<PushMessage>? _foregroundSubscription;

  // Evita abrir una cita antes de terminar la restauración de sesión.
  bool _sessionResolved = false;

  // Conserva temporalmente una notificación pendiente.
  int? _pendingCitaId;

  @override
  void initState() {
    super.initState();

    LocalPushNotifications.initialize().catchError((Object error) {
      debugPrint('Error inicializando notificaciones locales: $error');
    });

    _openSubscription = PushRuntime.coordinator.openedCitaIds.listen(_openCita);

    _foregroundSubscription = PushRuntime.coordinator.foregroundMessages.listen(
      _showForegroundMessage,
    );

    // No abrir todavía: AuthGate debe validar primero la sesión.
    _pendingCitaId = PushRuntime.coordinator.takePendingCitaId();
  }

  @override
  void dispose() {
    _openSubscription?.cancel();
    _foregroundSubscription?.cancel();
    super.dispose();
  }

  void _onSessionResolved(bool autenticada) {
    if (!mounted) return;

    setState(() {
      _sessionResolved = true;
    });

    if (!autenticada) {
      _pendingCitaId = null;
      return;
    }

    final pending = _pendingCitaId;
    _pendingCitaId = null;

    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openCita(pending);
        }
      });
    }
  }

  Future<void> _openCita(int citaId) async {
    if (citaId <= 0) return;

    // Esperar a que AuthGate termine la validación.
    if (!_sessionResolved) {
      _pendingCitaId = citaId;
      return;
    }

    if (!await TokenStorage().hasToken()) return;

    _navigatorKey.currentState?.push<void>(
      MaterialPageRoute(builder: (_) => CitaDetallePage(citaId: citaId)),
    );
  }

  void _showForegroundMessage(PushMessage message) {
    LocalPushNotifications.show(message).catchError((Object error) {
      debugPrint('Error mostrando notificación local: $error');
    });

    final citaId = message.citaId;

    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Tienes una nueva notificación.'),
          action: citaId == null
              ? null
              : SnackBarAction(
                  label: 'Ver cita',
                  onPressed: () => _openCita(citaId),
                ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Clínica Oftalmológica',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),

      // Recuperación automática de la sesión del paciente.
      home: AuthGate(onSessionResolved: _onSessionResolved),
    );
  }
}
