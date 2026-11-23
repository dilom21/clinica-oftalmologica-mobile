import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/core/session/sesion_clinica.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/pages/chatbot_page.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/pages/citas_page.dart';
import 'package:clinica_oftalmologica_mobile/features/home/pages/inicio_page.dart';
import 'package:clinica_oftalmologica_mobile/features/home/pages/main_navigation_page.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/pagos_service.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/stripe_payment_service.dart';

import 'soporte_chatbot.dart';

const ClinicaSesion _clinica = ClinicaSesion(
  codigo: 'CLINICA',
  nombre: 'Clínica Ficticia',
);

const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void _mockSecureStorage(Map<String, String> almacen) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
        switch (call.method) {
          case 'read':
            return almacen[call.arguments['key'] as String];
          case 'write':
            almacen[call.arguments['key'] as String] =
                call.arguments['value'] as String;
            return null;
          case 'delete':
            almacen.remove(call.arguments['key'] as String);
            return null;
          default:
            return null;
        }
      });
}

PagosService _pagosService() {
  return PagosService(
    client: MockClient((http.Request request) async {
      if (request.url.path == '/pagos/mis-consultas' ||
          request.url.path == '/pagos/mis-pagos') {
        return http.Response(
          jsonEncode(const <Object>[]),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode(<String, String>{'detail': 'no esperado'}),
        500,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }),
    leerToken: () async => 'jwt',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  testWidgets('Inicio muestra la tarjeta premium después de la próxima cita', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var conversar = 0;
    var hablar = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: InicioPage(
          clinica: _clinica,
          pacienteService: PacienteFalso(),
          agendaService: AgendaFalsa(),
          onAbrirChatbot: () => conversar++,
          onAbrirChatVoz: () => hablar++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inicio-asistente')), findsOneWidget);
    expect(find.text('ASISTENTE VIRTUAL'), findsOneWidget);
    expect(find.text('¿En qué podemos ayudarte hoy?'), findsOneWidget);

    final double yCita = tester
        .getTopLeft(find.byKey(const Key('inicio-proxima-cita')))
        .dy;
    final double yAsistente = tester
        .getTopLeft(find.byKey(const Key('inicio-asistente')))
        .dy;
    expect(yAsistente, greaterThan(yCita));

    await tester.ensureVisible(
      find.byKey(const Key('inicio-asistente-conversar')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inicio-asistente-conversar')));
    await tester.tap(find.byKey(const Key('inicio-asistente-hablar')));

    expect(conversar, 1);
    expect(hablar, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tarjeta de Inicio soporta texto al 200% sin desbordar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) {
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          );
        },
        home: InicioPage(
          clinica: _clinica,
          pacienteService: PacienteFalso(),
          agendaService: AgendaFalsa(),
          onAbrirChatbot: () {},
          onAbrirChatVoz: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('inicio-asistente')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('inicio-asistente')), findsOneWidget);
  });

  testWidgets('desde la barra inferior se abre el chat sin convertirlo en pestaña', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _mockSecureStorage(<String, String>{
      'access_token': 'jwt',
      'empresa_codigo': 'CLINICA',
      'empresa_nombre': 'Clínica Ficticia',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MainNavigationPage(
          pagosService: _pagosService(),
          stripeService: StripePaymentService(publishableKey: 'pk_test_fake'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    final etiquetas = tester
        .widgetList<NavigationDestination>(
          find.byType(NavigationDestination),
        )
        .map((destino) => destino.label)
        .toSet();
    expect(
      etiquetas,
      containsAll(<String>['Inicio', 'Citas', 'Pagos', 'Avisos', 'Perfil']),
    );
    expect(etiquetas, isNot(contains('Asistente')));

    await tester.ensureVisible(
      find.byKey(const Key('inicio-asistente-conversar')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inicio-asistente-conversar')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatbotPage), findsOneWidget);
    final compartido = tester
        .widget<ChatbotPage>(find.byType(ChatbotPage))
        .controller!;
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.byKey(const Key('chatbot-volver')));
    await tester.pumpAndSettle();

    expect(find.byType(InicioPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    // Una mutación de citas desde otra pestaña debe alcanzar el controlador
    // compartido, no limitarse al refresco visual de Inicio.
    final citas = tester.widget<CitasPage>(
      find.byType(CitasPage, skipOffstage: false),
    );
    citas.onCitasCambiadas?.call();
    await tester.pumpAndSettle();
    expect(compartido.tarjetasInvalidas, isTrue);
  });
}
