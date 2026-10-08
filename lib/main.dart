import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'core/config/stripe_config.dart';
import 'features/authentication_security/pages/login/login_page.dart';

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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Centro Oftalmológico Visión Clara',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),

      //significa que la primera pagina que se va a mostrar es la de login
      home: const LoginPage(),
    );
  }
}
