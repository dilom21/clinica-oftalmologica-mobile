import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/pagos/pages/comprobante_pago_page.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/comprobante_archivo_service.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/pagos_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

http.Response _pdf({String nombre = 'comprobante_pago_2.pdf'}) =>
    http.Response.bytes(
      utf8.encode('%PDF-1.4 comprobante de pago'),
      200,
      headers: {
        'content-type': 'application/pdf',
        'content-disposition': 'attachment; filename="$nombre"',
      },
    );

/// Servicio de archivo falso: no invoca plugins nativos en las pruebas.
class _ArchivoFake extends ComprobanteArchivoService {
  _ArchivoFake({
    this.rutaGuardado,
    this.falloGuardar = false,
    this.falloCompartir = false,
  });

  final String? rutaGuardado;
  final bool falloGuardar;
  final bool falloCompartir;

  int guardados = 0;
  int compartidos = 0;
  Uint8List? ultimosBytes;
  String? ultimoNombre;

  @override
  Future<String?> guardarComo(Uint8List bytes, String nombreArchivo) async {
    guardados++;
    ultimosBytes = bytes;
    ultimoNombre = nombreArchivo;

    if (falloGuardar) {
      throw const ComprobanteArchivoException(
        'No se pudo guardar el comprobante.',
      );
    }

    return rutaGuardado;
  }

  @override
  Future<void> compartir(Uint8List bytes, String nombreArchivo) async {
    compartidos++;

    if (falloCompartir) {
      throw const ComprobanteArchivoException(
        'No se pudo compartir el comprobante.',
      );
    }
  }
}

Widget _visorFalso(
  BuildContext context,
  Uint8List bytes,
  String nombreArchivo,
) => const SizedBox(key: Key('visor-falso'));

PagosService _service(Future<http.Response> Function(http.Request) handler) =>
    PagosService(client: MockClient(handler), leerToken: () async => 'token');

Future<void> _pump(
  WidgetTester tester,
  PagosService service, {
  ComprobanteArchivoService archivo = const ComprobanteArchivoService(),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ComprobantePagoPage(
        pagoId: 2,
        pagosService: service,
        archivoService: archivo,
        visor: _visorFalso,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Muestra el SnackBar esperado y deja pasar su temporizador (sin timers
/// pendientes al terminar la prueba).
Future<void> _confirmarSnack(WidgetTester tester, String mensaje) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text(mensaje), findsOneWidget);
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('descarga el PDF autenticado y lo muestra con acciones', (
    tester,
  ) async {
    String? accept;
    final service = _service((request) async {
      accept = request.headers['Accept'];
      expect(request.url.path, '/pagos/mis-pagos/2/comprobante');
      expect(request.headers['Authorization'], 'Bearer token');
      return _pdf();
    });

    await _pump(tester, service);

    expect(accept, 'application/pdf');
    expect(find.byKey(const Key('visor-falso')), findsOneWidget);
    expect(find.text('Guardar PDF'), findsOneWidget);
    expect(find.text('Compartir'), findsOneWidget);
  });

  testWidgets('404 muestra error y permite reintentar', (tester) async {
    var intentos = 0;
    final service = _service((request) async {
      intentos++;
      if (intentos == 1) {
        return _json({'detail': 'Comprobante no disponible'}, 404);
      }
      return _pdf();
    });

    await _pump(tester, service);

    expect(find.text('No se pudo mostrar el comprobante'), findsOneWidget);
    expect(
      find.text('El comprobante no está disponible para este pago.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('visor-falso')), findsOneWidget);
  });

  testWidgets('409 (pago no aprobado) muestra el mensaje del backend', (
    tester,
  ) async {
    final service = _service(
      (r) async => _json({
        'detail':
            'El comprobante solo esta disponible para pagos APROBADOS '
            '(estado actual: PENDIENTE)',
      }, 409),
    );

    await _pump(tester, service);

    expect(
      find.textContaining('solo esta disponible para pagos APROBADOS'),
      findsOneWidget,
    );
    expect(find.text('Guardar PDF'), findsNothing);
  });

  testWidgets('error de conexión muestra un mensaje entendible', (
    tester,
  ) async {
    final service = _service(
      (r) async => throw http.ClientException('sin red'),
    );

    await _pump(tester, service);

    expect(
      find.textContaining('No se pudo conectar con el servidor'),
      findsOneWidget,
    );
  });

  testWidgets('un 200 sin PDF no se muestra como comprobante', (tester) async {
    final service = _service(
      (r) async =>
          http.Response('esto no es un pdf', 200, headers: _jsonHeaders),
    );

    await _pump(tester, service);

    expect(
      find.textContaining('no tiene un formato PDF válido'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('visor-falso')), findsNothing);
  });

  testWidgets('"Guardar PDF" usa el selector y confirma el guardado', (
    tester,
  ) async {
    final service = _service((r) async => _pdf());
    final archivo = _ArchivoFake(
      rutaGuardado: '/Download/comprobante_pago_2.pdf',
    );

    await _pump(tester, service, archivo: archivo);

    await tester.tap(find.text('Guardar PDF'));
    await _confirmarSnack(tester, 'Comprobante guardado correctamente.');

    expect(archivo.guardados, 1);
    expect(archivo.ultimoNombre, 'comprobante_pago_2.pdf');
    expect(archivo.ultimosBytes, isNotNull);
  });

  testWidgets('cancelar el guardado no se reporta como error', (tester) async {
    final service = _service((r) async => _pdf());
    final archivo = _ArchivoFake();

    await _pump(tester, service, archivo: archivo);

    await tester.tap(find.text('Guardar PDF'));
    await _confirmarSnack(tester, 'Guardado cancelado.');

    expect(archivo.guardados, 1);
  });

  testWidgets('un fallo al guardar se informa al paciente', (tester) async {
    final service = _service((r) async => _pdf());
    final archivo = _ArchivoFake(falloGuardar: true);

    await _pump(tester, service, archivo: archivo);

    await tester.tap(find.text('Guardar PDF'));
    await _confirmarSnack(tester, 'No se pudo guardar el comprobante.');
  });

  testWidgets('"Compartir" usa el menú nativo del teléfono', (tester) async {
    final service = _service((r) async => _pdf());
    final archivo = _ArchivoFake();

    await _pump(tester, service, archivo: archivo);

    await tester.tap(find.text('Compartir'));
    await tester.pumpAndSettle();

    expect(archivo.compartidos, 1);
  });

  testWidgets('un fallo al compartir se informa al paciente', (tester) async {
    final service = _service((r) async => _pdf());
    final archivo = _ArchivoFake(falloCompartir: true);

    await _pump(tester, service, archivo: archivo);

    await tester.tap(find.text('Compartir'));
    await _confirmarSnack(tester, 'No se pudo compartir el comprobante.');
  });
}
