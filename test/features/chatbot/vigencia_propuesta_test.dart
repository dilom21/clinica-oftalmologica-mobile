import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chatbot_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/models/chatbot_models.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/services/chatbot_service.dart';

import 'soporte_chatbot.dart';

TarjetaPropuestaCita _propuesta({
  int id = 5,
  int dia = 27,
  String inicio = '14:00:00',
}) => TarjetaPropuestaCita(
  oftalmologoId: id,
  fecha: DateTime(2026, 11, dia),
  horaInicio: inicio,
  horaFin: '14:30:00',
);

RespuestaChatbot _respuesta(
  List<TarjetaChatbot> tarjetas, {
  String texto = 'Respuesta',
}) => RespuestaChatbot(
  conversacionId: 'conv-1',
  respuesta: texto,
  textoVoz: texto,
  tipo: TipoRespuestaChatbot.texto,
  tarjetas: tarjetas,
);

void main() {
  late ApiChatbotFalsa api;
  late ChatbotController ctrl;
  late DateTime ahora;
  late String? token;

  setUp(() {
    ahora = DateTime(2026, 11, 23, 16, 50);
    token = 'jwt';
    api = ApiChatbotFalsa()..respuesta = _respuesta([_propuesta()]);
    ctrl = ChatbotController(
      api: api,
      leerToken: () async => token,
      ahora: () => ahora,
    );
  });
  tearDown(() => ctrl.dispose());

  test('401 en una cortesía invalida también la propuesta pendiente', () async {
    final mensaje = (await ctrl.enviar('Cita'))!;
    api.errorEnviar = const ChatbotException(
      'Sesión expirada',
      statusCode: 401,
    );
    await ctrl.enviar('Gracias');
    expect(ctrl.propuestaVigente(mensaje.id, 0), isFalse);
    expect(await ctrl.prepararPropuesta(mensaje.id, 0), isNull);
    expect(ctrl.conversacionId, isNull);
  });

  test(
    'una propuesta reciente es accionable y usa los datos recibidos',
    () async {
      final mensaje = (await ctrl.enviar('Cita con Salet Ejemplo'))!;
      expect(ctrl.propuestaVigente(mensaje.id, 0), isTrue);
      final seleccion = await ctrl.prepararPropuesta(mensaje.id, 0);
      expect(seleccion?.oftalmologoId, 5);
      expect(seleccion?.fecha, DateTime(2026, 11, 27));
      expect(seleccion?.horaInicio, '14:00:00');
    },
  );

  test(
    'propuesta → Okay muchas gracias → sigue activa en texto y voz',
    () async {
      final mensaje = (await ctrl.enviar('Cita'))!;
      api.respuesta = _respuesta([], texto: '¡De nada!');
      for (final social in [
        'Okay muchas gracias',
        '¡Perfecto, gracias!',
        'Entendido',
      ]) {
        await ctrl.enviar(social, modalidad: ModalidadChat.voz);
        expect(ctrl.propuestaVigente(mensaje.id, 0), isTrue);
      }
      expect(api.crearLlamadas, 1);
      expect(ctrl.conversacionId, 'conv-1');
    },
  );

  test(
    'nueva propuesta sustituye incluso si reutiliza el mismo objeto/valores',
    () async {
      final primera = (await ctrl.enviar('Cita'))!;
      final segunda = (await ctrl.enviar('Otra propuesta'))!;
      expect(ctrl.propuestaVigente(primera.id, 0), isFalse);
      expect(ctrl.propuestaVigente(segunda.id, 0), isTrue);
      expect(await ctrl.prepararPropuesta(primera.id, 0), isNull);
    },
  );

  for (final cambio in [
    'Mejor con otro profesional',
    'Para el 28 de noviembre',
    'A las 15:00',
    'Gracias, pero cambia al 28',
    'No gracias',
    'Okay con otro médico',
  ]) {
    test(
      'cambio de contexto sin tarjetas retira la selección: $cambio',
      () async {
        final mensaje = (await ctrl.enviar('Cita'))!;
        api.respuesta = _respuesta([], texto: '¡De nada!');
        await ctrl.enviar(cambio);
        expect(ctrl.propuestaVigente(mensaje.id, 0), isFalse);
        await ctrl.enviar('Muchas gracias');
        expect(
          ctrl.propuestaVigente(mensaje.id, 0),
          isFalse,
          reason: 'ningún mensaje genérico reactiva una tarjeta histórica',
        );
      },
    );
  }

  test(
    'cambio de datos con propuesta nueva solo habilita la nueva selección',
    () async {
      final primera = (await ctrl.enviar('Cita'))!;
      api.respuesta = _respuesta([_propuesta(id: 8, dia: 28)]);
      final segunda = (await ctrl.enviar('Otro profesional y otra fecha'))!;
      expect(ctrl.propuestaVigente(primera.id, 0), isFalse);
      expect(ctrl.propuestaVigente(segunda.id, 0), isTrue);
      final seleccion = await ctrl.prepararPropuesta(segunda.id, 0);
      expect(seleccion?.oftalmologoId, 8);
      expect(seleccion?.fecha, DateTime(2026, 11, 28));
    },
  );

  test('dos propuestas en un mensaje no inventan una selección', () async {
    api.respuesta = _respuesta([_propuesta(), _propuesta(id: 8)]);
    final mensaje = (await ctrl.enviar('Opciones'))!;
    expect(ctrl.propuestaVigente(mensaje.id, 0), isFalse);
    expect(ctrl.propuestaVigente(mensaje.id, 1), isFalse);
  });

  test(
    'datos estructurados contradictorios prevalecen sobre una cortesía',
    () async {
      final mensaje = (await ctrl.enviar('Cita'))!;
      api.respuesta = _respuesta([
        TarjetaDisponibilidad(
          oftalmologoId: 8,
          fecha: DateTime(2026, 11, 28),
          intervalos: const [],
        ),
      ]);
      await ctrl.enviar('Gracias');
      expect(ctrl.propuestaVigente(mensaje.id, 0), isFalse);
    },
  );

  test('una cita real para la selección retira la propuesta', () async {
    final mensaje = (await ctrl.enviar('Cita'))!;
    api.respuesta = _respuesta([
      TarjetaCitasPropias(
        citas: [
          CitaPropiaChat(
            id: 70,
            oftalmologoId: 5,
            fecha: DateTime(2026, 11, 27),
            horaInicio: '14:00:00',
            horaFin: '14:30:00',
            estado: 'PROGRAMADA',
          ),
        ],
      ),
    ]);
    await ctrl.enviar('Gracias');
    expect(ctrl.propuestaVigente(mensaje.id, 0), isFalse);
  });

  test(
    'registro real no se deshace con una respuesta social posterior',
    () async {
      final mensaje = (await ctrl.enviar('Cita'))!;
      ctrl.invalidarTarjetas(evento: 'Cita registrada.');
      api.respuesta = _respuesta([], texto: '¡De nada!');
      await ctrl.enviar('Gracias');
      expect(ctrl.propuestaVigente(mensaje.id, 0), isFalse);
    },
  );

  test('registro durante una petición descarta propuestas de la instantánea anterior', () async {
    final mensaje = (await ctrl.enviar('Cita'))!;
    final pendiente = Completer<RespuestaChatbot>();
    api.alEnviar = (_, _) => pendiente.future;
    final envio = ctrl.enviar('Otra propuesta');
    await Future<void>.delayed(Duration.zero);
    ctrl.invalidarTarjetas();
    pendiente.complete(_respuesta([_propuesta()]));
    final nueva = (await envio)!;
    expect(ctrl.propuestaVigente(mensaje.id, 0), isFalse);
    expect(ctrl.propuestaVigente(nueva.id, 0), isFalse);
  });

  for (final accion in [
    'reiniciar',
    'cerrar sesión',
    'JWT',
    'TTL',
    'hora vencida',
  ]) {
    test(
      '$accion impide continuar y no reutiliza tarjetas anteriores',
      () async {
        if (accion == 'hora vencida') api.expiraEnSegundos = 7 * 24 * 3600;
        final mensaje = (await ctrl.enviar('Cita'))!;
        switch (accion) {
          case 'reiniciar':
            await ctrl.nuevaConversacion();
          case 'cerrar sesión':
            ctrl.cerrarSesion();
          case 'JWT':
            token = null;
          case 'TTL':
            ahora = ahora.add(const Duration(minutes: 31));
          case 'hora vencida':
            ahora = DateTime(2026, 11, 27, 14, 1);
        }
        expect(await ctrl.prepararPropuesta(mensaje.id, 0), isNull);
      },
    );
  }

  test('timeout incierto de una cortesía no permite asumir que el contexto sigue igual', () async {
    final mensaje = (await ctrl.enviar('Cita'))!;
    api.errorEnviar = const ChatbotException(
      'Resultado incierto',
      resultadoIncierto: true,
    );
    await ctrl.enviar('Okay gracias');
    expect(ctrl.propuestaVigente(mensaje.id, 0), isFalse);
  });

  for (final campo in <String, Object?>{
    'oftalmologo_id': 0,
    'fecha': '2026-02-30',
    'hora_inicio': '25:00:00',
    'hora_fin': '13:00:00',
    'reservada': true,
    'requiere_confirmacion': false,
  }.entries) {
    test('propuesta con ${campo.key} inválido no es accionable', () async {
      final json = <String, dynamic>{
        'tipo': 'propuesta_cita',
        'oftalmologo_id': 5,
        'fecha': '2026-11-27',
        'hora_inicio': '14:00:00',
        'hora_fin': '14:30:00',
        campo.key: campo.value,
      };
      final propuesta = TarjetaPropuestaCita.fromJson(json);
      api.respuesta = _respuesta([propuesta]);
      final mensaje = (await ctrl.enviar('Cita'))!;
      expect(propuesta.datosValidos, isFalse);
      expect(ctrl.propuestaVigente(mensaje.id, 0), isFalse);
    });
  }
}
