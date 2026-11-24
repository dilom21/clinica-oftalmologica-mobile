import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clinica_oftalmologica_mobile/core/session/sesion_clinica.dart';
import 'package:clinica_oftalmologica_mobile/features/catalogo/pages/catalogo_page.dart';
import 'package:clinica_oftalmologica_mobile/features/catalogo/services/catalogo_service.dart';
import 'package:clinica_oftalmologica_mobile/features/catalogo/models/servicio_catalogo.dart';

class Falso extends CatalogoService {
  bool fallar = false;
  @override
  Future<List<ServicioCatalogo>> listar({
    String busqueda = '',
    int offset = 0,
    int limite = 20,
  }) async {
    if (fallar) throw const CatalogoException('Sin conexión');
    return busqueda == 'ausente'
        ? []
        : [
            const ServicioCatalogo(
              id: 1,
              nombre: 'Consulta general',
              precio: 100,
              duracion: 30,
            ),
          ];
  }

  @override
  Future<ServicioCatalogo> detalle(int id) async => const ServicioCatalogo(
    id: 1,
    nombre: 'Consulta general',
    descripcion: 'Evaluación visual',
  );
}

class Pendiente extends CatalogoService {
  final solicitudes = <Completer<List<ServicioCatalogo>>>[];
  @override
  Future<List<ServicioCatalogo>> listar({
    String busqueda = '',
    int offset = 0,
    int limite = 20,
  }) {
    final c = Completer<List<ServicioCatalogo>>();
    solicitudes.add(c);
    return c.future;
  }
}

class Paginado extends Falso {
  final offsets = <int>[];
  @override
  Future<List<ServicioCatalogo>> listar({
    String busqueda = '',
    int offset = 0,
    int limite = 20,
  }) async {
    offsets.add(offset);
    return offset == 0
        ? List.generate(
            20,
            (i) => ServicioCatalogo(id: i, nombre: 'Servicio $i'),
          )
        : [];
  }
}

class Expirado extends Falso {
  @override
  Future<List<ServicioCatalogo>> listar({
    String busqueda = '',
    int offset = 0,
    int limite = 20,
  }) async {
    throw const CatalogoException('Sesión expirada', statusCode: 401);
  }
}

void main() {
  testWidgets('busca automaticamente y borrar restaura el catalogo', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: CatalogoPage(service: Falso())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ausente');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay servicios disponibles con esta búsqueda.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Consulta general'), findsOneWidget);
  });
  testWidgets('ver todos restaura lista y limpia campo sin salir', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: CatalogoPage(service: Falso())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ausente');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver todos los servicios'));
    await tester.pumpAndSettle();
    expect(find.text('Consulta general'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });
  testWidgets('agrupar escritura y cancelar temporizador al cerrar', (
    tester,
  ) async {
    final servicio = Pendiente();
    await tester.pumpWidget(MaterialApp(home: CatalogoPage(service: servicio)));
    servicio.solicitudes[0].complete([]);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.enterText(find.byType(TextField), 'ausente');
    await tester.pump(const Duration(milliseconds: 200));
    expect(servicio.solicitudes.length, 1);
    await tester.pump(const Duration(milliseconds: 150));
    expect(servicio.solicitudes.length, 2);
    servicio.solicitudes[1].complete([]);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'otra');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 1));
    expect(servicio.solicitudes.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('descarta respuesta vieja y limpia datos al cambiar empresa', (
    tester,
  ) async {
    final servicio = Pendiente();
    Widget app(String codigo) => MaterialApp(
      home: CatalogoPage(
        service: servicio,
        clinica: ClinicaSesion(codigo: codigo, nombre: codigo),
      ),
    );
    await tester.pumpWidget(app('ALPHA'));
    await tester.pumpWidget(app('BETA'));
    servicio.solicitudes[1].complete([
      const ServicioCatalogo(id: 1, nombre: 'Solo BETA'),
    ]);
    await tester.pumpAndSettle();
    servicio.solicitudes[0].complete([
      const ServicioCatalogo(id: 1, nombre: 'Solo ALPHA'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Solo BETA'), findsOneWidget);
    expect(find.text('Solo ALPHA'), findsNothing);
  });
  testWidgets('cargar mas respeta offset', (tester) async {
    final servicio = Paginado();
    await tester.pumpWidget(MaterialApp(home: CatalogoPage(service: servicio)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Cargar más'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Cargar más'));
    await tester.pumpAndSettle();
    expect(servicio.offsets, [0, 20]);
    expect(find.text('Cargar más'), findsNothing);
  });
  testWidgets('401 notifica cierre de sesion', (tester) async {
    var llamadas = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CatalogoPage(
          service: Expirado(),
          onSesionInvalida: () => llamadas++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(llamadas, 1);
  });
  testWidgets('pantalla pequena no desborda', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: CatalogoPage(service: Falso())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('lista, clinica y detalle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CatalogoPage(
          service: Falso(),
          clinica: const ClinicaSesion(codigo: 'BETA', nombre: 'Clínica Beta'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Clínica Beta'), findsOneWidget);
    await tester.tap(find.text('Consulta general'));
    await tester.pumpAndSettle();
    expect(find.text('Evaluación visual'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('busqueda sin resultados', (tester) async {
    await tester.pumpWidget(MaterialApp(home: CatalogoPage(service: Falso())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ausente');
    await tester.tap(find.widgetWithText(FilledButton, 'Buscar'));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay servicios disponibles con esta búsqueda.'),
      findsOneWidget,
    );
  });
  testWidgets('reintento despues de error', (tester) async {
    final servicio = Falso()..fallar = true;
    await tester.pumpWidget(MaterialApp(home: CatalogoPage(service: servicio)));
    await tester.pumpAndSettle();
    expect(find.text('Sin conexión'), findsOneWidget);
    servicio.fallar = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Consulta general'), findsOneWidget);
  });
}
