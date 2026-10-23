import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/authentication_security/models/auth_models.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/pages/register/register_page.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/services/auth_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

const _empresa = EmpresaTenant(codigo: 'CLN-A', nombre: 'Visión Clara Norte');

/// Cliente simulado del registro tenant.
///
/// Nunca crea pacientes reales: solo responde con el código HTTP y el cuerpo
/// configurados, y registra las peticiones recibidas.
class _RegistroFake {
  _RegistroFake({
    this.status = 201,
    this.body,
    this.esperar,
    this.errorConexion = false,
  });

  final int status;
  final Map<String, dynamic>? body;
  final Completer<void>? esperar;
  final bool errorConexion;

  /// Peticiones recibidas, con el formato `MÉTODO ruta`.
  final List<String> rutas = <String>[];

  /// Último cuerpo JSON enviado por la app.
  Map<String, dynamic>? cuerpo;

  MockClient get cliente => MockClient((request) async {
    rutas.add('${request.method} ${request.url.path}');

    if (errorConexion) {
      throw http.ClientException('sin red');
    }

    if (request.method == 'POST' &&
        request.url.path == '/seguridad/tenant/registro-paciente') {
      cuerpo = jsonDecode(request.body) as Map<String, dynamic>;

      if (esperar != null) {
        await esperar!.future;
      }

      return http.Response(
        jsonEncode(body ?? {'message': 'Cuenta creada correctamente'}),
        status,
        headers: _jsonHeaders,
      );
    }

    return http.Response('{}', 404, headers: _jsonHeaders);
  });
}

/// Correo con el que `RegisterPage` cierra la pantalla.
String? _resultado;

/// Monta `RegisterPage` dentro de una ruta y la abre.
///
/// Se usa una ventana de prueba más alta que la de por defecto (800x600) para
/// que todo el formulario quede visible al pulsar sus campos, y un `MaterialApp`
/// con clave nueva en cada montaje para no arrastrar la ruta de una iteración
/// anterior.
Future<void> _pumpRegistro(
  WidgetTester tester,
  AuthService service, {
  EmpresaTenant empresa = _empresa,
}) async {
  _resultado = null;

  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                _resultado = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) =>
                        RegisterPage(empresa: empresa, authService: service),
                  ),
                );
              },
              child: const Text('Abrir registro'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Abrir registro'));
  await tester.pumpAndSettle();
}

/// Campos de texto del formulario de registro, acotados a `RegisterPage`.
Finder _campos() => find.descendant(
  of: find.byType(RegisterPage),
  matching: find.byType(TextFormField),
);

/// Selector de sexo del formulario de registro.
Finder _selectorSexo() => find.descendant(
  of: find.byType(RegisterPage),
  matching: find.byType(DropdownButtonFormField<String>),
);

/// Desplaza [finder] a la vista y lo toca (el formulario es más alto que la
/// pantalla de prueba de 800x600).
Future<void> _toque(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Completa el formulario con datos válidos.
Future<void> _llenarFormulario(WidgetTester tester) async {
  final campos = _campos();

  await tester.enterText(campos.at(0), '12345678');
  await tester.enterText(campos.at(1), 'Ana');
  await tester.enterText(campos.at(2), 'Pérez');

  // Fecha de nacimiento: el selector abre con una fecha válida por defecto.
  await _toque(tester, campos.at(3));
  await _toque(tester, find.text('Aceptar'));

  await _toque(tester, _selectorSexo());
  await _toque(tester, find.text('Femenino').last);

  await tester.enterText(campos.at(4), '70000000');
  await tester.enterText(campos.at(5), 'Familiar 71111111');
  await tester.enterText(campos.at(6), 'Av. Ejemplo 123');
  await tester.enterText(campos.at(7), 'ana@correo.com');
  await tester.enterText(campos.at(8), 'ClaveSegura123!');
  await tester.enterText(campos.at(9), 'ClaveSegura123!');
}

/// Pulsa el botón "Crear cuenta" y deja terminar la petición.
Future<void> _enviar(WidgetTester tester) async {
  final boton = find.byKey(const Key('register-submit'));
  await tester.ensureVisible(boton);
  await tester.pumpAndSettle();
  await tester.tap(boton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('muestra la clínica en la que se está registrando', (
    tester,
  ) async {
    await _pumpRegistro(tester, AuthService(client: _RegistroFake().cliente));

    expect(find.byKey(const Key('register-clinica')), findsOneWidget);
    expect(find.text('Te estás registrando en'), findsOneWidget);
    expect(find.text('Visión Clara Norte'), findsOneWidget);
    expect(find.text('Código de clínica: CLN-A'), findsOneWidget);
  });

  testWidgets('envía empresa_codigo y vuelve al login con el correo', (
    tester,
  ) async {
    final fake = _RegistroFake();

    await _pumpRegistro(tester, AuthService(client: fake.cliente));
    await _llenarFormulario(tester);
    await _enviar(tester);

    expect(fake.rutas, ['POST /seguridad/tenant/registro-paciente']);
    expect(fake.rutas, isNot(contains('POST /seguridad/registro-paciente')));
    expect(fake.cuerpo, isNotNull);

    final cuerpo = fake.cuerpo!;
    expect(cuerpo['empresa_codigo'], 'CLN-A');
    expect(cuerpo['ci'], '12345678');
    expect(cuerpo['nombres'], 'Ana');
    expect(cuerpo['apellidos'], 'Pérez');
    expect(cuerpo['sexo'], 'F');
    expect(cuerpo['telefono'], '70000000');
    expect(cuerpo['contacto_emergencia'], 'Familiar 71111111');
    expect(cuerpo['direccion'], 'Av. Ejemplo 123');
    expect(cuerpo['correo'], 'ana@correo.com');
    expect(cuerpo['password'], 'ClaveSegura123!');
    expect(cuerpo.containsKey('tenant_id'), isFalse);
    expect(cuerpo.containsKey('database_name'), isFalse);
    expect(cuerpo.containsKey('rol_id'), isFalse);
    expect(cuerpo.containsKey('usuario_id'), isFalse);

    expect(find.text('Cuenta creada correctamente'), findsOneWidget);
    expect(find.textContaining('Visión Clara Norte'), findsWidgets);

    await tester.tap(find.text('Ir a iniciar sesión'));
    await tester.pumpAndSettle();

    expect(_resultado, 'ana@correo.com');
    expect(find.text('Abrir registro'), findsOneWidget);
  });

  testWidgets('registra únicamente en la clínica recibida', (tester) async {
    const otra = EmpresaTenant(codigo: 'CLN-B', nombre: 'Visión Clara Sur');
    final fake = _RegistroFake();

    await _pumpRegistro(
      tester,
      AuthService(client: fake.cliente),
      empresa: otra,
    );
    await _llenarFormulario(tester);
    await _enviar(tester);

    expect(fake.cuerpo!['empresa_codigo'], 'CLN-B');
    expect(find.text('Visión Clara Sur'), findsOneWidget);
    expect(find.text('Visión Clara Norte'), findsNothing);
    expect(fake.rutas, hasLength(1));
  });

  testWidgets('no registra sin una clínica seleccionada', (tester) async {
    const sinClinica = EmpresaTenant(codigo: '', nombre: 'Sin clínica');
    final fake = _RegistroFake();

    await _pumpRegistro(
      tester,
      AuthService(client: fake.cliente),
      empresa: sinClinica,
    );
    await _llenarFormulario(tester);
    await _enviar(tester);

    expect(fake.rutas, isEmpty);
    expect(find.text(AuthService.mensajeClinicaRequerida), findsOneWidget);
  });

  testWidgets('valida los campos obligatorios antes de enviar', (tester) async {
    final fake = _RegistroFake();

    await _pumpRegistro(tester, AuthService(client: fake.cliente));
    await _enviar(tester);

    expect(find.text('El campo CI es obligatorio'), findsOneWidget);
    expect(find.text('El campo nombres es obligatorio'), findsOneWidget);
    expect(find.text('El campo apellidos es obligatorio'), findsOneWidget);
    expect(find.text('Selecciona tu fecha de nacimiento'), findsOneWidget);
    expect(find.text('Selecciona tu sexo'), findsOneWidget);
    expect(find.text('El correo electrónico es obligatorio'), findsOneWidget);
    expect(find.text('La contraseña es obligatoria'), findsOneWidget);
    expect(find.text('Confirma tu contraseña'), findsOneWidget);
    expect(fake.rutas, isEmpty);
  });

  testWidgets('mantiene la política de contraseña', (tester) async {
    final fake = _RegistroFake();

    await _pumpRegistro(tester, AuthService(client: fake.cliente));
    await _llenarFormulario(tester);

    final campos = _campos();
    await tester.enterText(campos.at(8), 'clavesegura!');
    await tester.enterText(campos.at(9), 'clavesegura!');
    await _enviar(tester);

    expect(find.text('Debe incluir una letra mayúscula'), findsOneWidget);
    expect(fake.rutas, isEmpty);
  });

  testWidgets('exige que las contraseñas coincidan', (tester) async {
    final fake = _RegistroFake();

    await _pumpRegistro(tester, AuthService(client: fake.cliente));
    await _llenarFormulario(tester);

    await tester.enterText(_campos().at(9), 'OtraClaveSegura123!');
    await _enviar(tester);

    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
    expect(fake.rutas, isEmpty);
  });

  testWidgets('un 409 de paciente existente pide verificar la identidad', (
    tester,
  ) async {
    final fake = _RegistroFake(
      status: 409,
      body: {
        'detail': 'Ya existe un paciente con estos datos en esta clínica.',
      },
    );

    await _pumpRegistro(tester, AuthService(client: fake.cliente));
    await _llenarFormulario(tester);
    await _enviar(tester);

    expect(find.text(AuthService.mensajePacienteExistente), findsOneWidget);
    expect(
      find.text(
        'Ya existe un registro con estos datos. Para vincular tu cuenta, '
        'debes verificar tu identidad directamente con la clínica.',
      ),
      findsOneWidget,
    );
    expect(find.text('Entendido'), findsOneWidget);
    expect(_resultado, isNull);
    expect(fake.rutas, ['POST /seguridad/tenant/registro-paciente']);

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterPage), findsOneWidget);
  });

  testWidgets('un correo duplicado se informa con el mensaje del backend', (
    tester,
  ) async {
    const detalle = 'El correo ya está registrado en esta clínica.';
    final fake = _RegistroFake(status: 409, body: {'detail': detalle});

    await _pumpRegistro(tester, AuthService(client: fake.cliente));
    await _llenarFormulario(tester);
    await _enviar(tester);

    expect(find.text(detalle), findsOneWidget);
    expect(find.text(AuthService.mensajePacienteExistente), findsNothing);
    expect(_resultado, isNull);
  });

  testWidgets('muestra mensajes claros para 403, 404, 422 y 503', (
    tester,
  ) async {
    final casos = <int, String>{
      403: AuthService.mensajeClinicaSinSuscripcion,
      404: AuthService.mensajeClinicaNoDisponible,
      422: 'Revisa los datos ingresados: no tienen el formato esperado.',
      503:
          'La clínica no está disponible en este momento. Inténtalo más tarde.',
    };

    for (final caso in casos.entries) {
      final fake = _RegistroFake(status: caso.key);

      await _pumpRegistro(tester, AuthService(client: fake.cliente));
      await _llenarFormulario(tester);
      await _enviar(tester);

      expect(find.text(caso.value), findsOneWidget, reason: '${caso.key}');
      expect(fake.rutas, hasLength(1));
      expect(_resultado, isNull);
    }
  });

  testWidgets('un error de conexión muestra un mensaje entendible', (
    tester,
  ) async {
    final fake = _RegistroFake(errorConexion: true);

    await _pumpRegistro(tester, AuthService(client: fake.cliente));
    await _llenarFormulario(tester);
    await _enviar(tester);

    expect(
      find.textContaining('No se pudo conectar con el servidor'),
      findsOneWidget,
    );
    expect(_resultado, isNull);
  });

  testWidgets('evita solicitudes duplicadas mientras se procesa', (
    tester,
  ) async {
    final esperar = Completer<void>();
    final fake = _RegistroFake(esperar: esperar);

    await _pumpRegistro(tester, AuthService(client: fake.cliente));
    await _llenarFormulario(tester);

    final boton = find.byKey(const Key('register-submit'));
    await tester.ensureVisible(boton);
    await tester.pumpAndSettle();
    await tester.tap(boton);
    await tester.pump();

    // Mientras la petición está en curso, el botón queda deshabilitado.
    await tester.tap(boton, warnIfMissed: false);
    await tester.pump();

    esperar.complete();
    await tester.pumpAndSettle();

    expect(fake.rutas, hasLength(1));
    expect(find.text('Cuenta creada correctamente'), findsOneWidget);
  });
}
