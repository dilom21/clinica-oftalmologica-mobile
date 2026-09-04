import 'package:flutter/material.dart';

import 'features/authentication_security/pages/login/login_page.dart';

void main() {
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3: true,
      ),

      //significa que la primera pagina que se va a mostrar es la de login
      home: const LoginPage(),
    );
  }
}