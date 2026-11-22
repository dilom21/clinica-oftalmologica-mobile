import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'core/config/stripe_config.dart';
import 'core/storage/token_storage.dart';
import 'features/authentication_security/pages/login/login_page.dart';
import 'features/citas/pages/cita_detalle_page.dart';
import 'features/notificaciones/services/push_runtime.dart';
import 'features/notificaciones/services/push_transport.dart';
import 'features/notificaciones/services/local_push_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa Stripe SOLO si hay una clave publicable configurada.
  // La clave se inyecta con --dart-define (nunca se hardcodea) y no se
  // registra en logs.
  if (StripeConfig.estaConfigurada) {
    try {
      Stripe.publishableKey = StripeConfig.publishableKey.trim();
      await Stripe.instance.applySettings();
    } on Exception {
      // Si falla la inicialización, el módulo Pagos lo avisa al paciente.
    }
  }

  // Si faltan archivos Firebase reales, falla de forma segura y la app sigue
  // disponible sin simular Push. No se registra configuración ni tokens.
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
    final pending = PushRuntime.coordinator.takePendingCitaId();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCita(pending));
    }
  }

  @override
  void dispose() {
    _openSubscription?.cancel();
    _foregroundSubscription?.cancel();
    super.dispose();
  }

  Future<void> _openCita(int citaId) async {
    if (citaId <= 0) return;
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
          // No se refleja contenido clínico del payload en primer plano.
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
      // Título genérico: la clínica real la identifica el login multitenant y
      // se muestra dentro de la app una vez autenticado el paciente.
      title: 'Clínica Oftalmológica',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),

      //significa que la primera pagina que se va a mostrar es la de login
      home: const LoginPage(),
    );
  }
}
