import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/features/chatbot/models/chatbot_models.dart';

void main() {
  test('conversación y respuesta de texto', () {
    final conversacion = ConversacionChatbot.fromJson(<String, dynamic>{
      'conversacion_id': '123e4567-e89b-42d3-a456-426614174000',
      'expira_en_segundos': 1800,
    });
    expect(conversacion.id, '123e4567-e89b-42d3-a456-426614174000');
    expect(conversacion.expiraEnSegundos, 1800);

    final respuesta = RespuestaChatbot.fromJson(<String, dynamic>{
      'conversacion_id': 'abc',
      'respuesta': '  Hola  ',
      'texto_voz': '',
      'tipo': 'texto',
      'tarjetas': <Object>[],
    });
    expect(respuesta.respuesta, 'Hola');
    expect(respuesta.textoVoz, 'Hola', reason: 'usa respuesta como respaldo');
    expect(respuesta.tipo, TipoRespuestaChatbot.texto);
    expect(respuesta.tarjetas, isEmpty);
    expect(respuesta.contieneInformacionPrivada, isFalse);
  });

  test(
    'respuesta de datos con tarjeta de servicios conserva Decimal y null',
    () {
      final respuesta = RespuestaChatbot.fromJson(<String, dynamic>{
        'conversacion_id': 'abc',
        'respuesta': 'Servicios',
        'texto_voz': 'Servicios',
        'tipo': 'datos',
        'tarjetas': <Object>[
          <String, dynamic>{
            'tipo': 'servicios',
            'privacidad': 'publica',
            'servicios': <Object>[
              <String, dynamic>{
                'id': 1,
                'nombre': 'Consulta',
                'descripcion': 'Evaluación',
                'precio': '100.50',
                'duracion_minutos': 30,
              },
              <String, dynamic>{
                'id': 2,
                'nombre': 'Sin precio',
                'descripcion': null,
                'precio': null,
                'duracion_minutos': null,
              },
            ],
            'busqueda': 'Consulta',
            'offset': 0,
            'hay_mas': null,
          },
        ],
      });

      expect(respuesta.tipo, TipoRespuestaChatbot.datos);
      final TarjetaServicios tarjeta =
          respuesta.tarjetas.single as TarjetaServicios;
      expect(tarjeta.servicios.first.precio, '100.50');
      expect(tarjeta.servicios.first.precioTexto, 'Bs 100.50');
      expect(tarjeta.servicios.last.precio, isNull);
      expect(tarjeta.servicios.last.precioTexto, 'Precio por consultar');
      expect(tarjeta.servicios.last.duracionMinutos, isNull);
      expect(tarjeta.servicios.last.duracionTexto, 'Duración no registrada');
      expect(tarjeta.hayMas, isNull, reason: 'null no significa false');
      expect(tarjeta.busqueda, 'Consulta');
    },
  );

  test('siete discriminadores se deserializan', () {
    const List<String> tipos = <String>[
      'servicios',
      'profesionales',
      'disponibilidad',
      'propuesta_cita',
      'citas_propias',
      'clinica',
      'navegacion',
    ];
    final List<Map<String, dynamic>> json = <Map<String, dynamic>>[
      <String, dynamic>{'tipo': 'servicios', 'servicios': <Object>[]},
      <String, dynamic>{'tipo': 'profesionales', 'profesionales': <Object>[]},
      <String, dynamic>{
        'tipo': 'disponibilidad',
        'oftalmologo_id': 1,
        'fecha': '2026-12-15',
        'intervalos': <Object>[],
        'franja': 'manana',
      },
      <String, dynamic>{
        'tipo': 'propuesta_cita',
        'oftalmologo_id': 1,
        'fecha': '2026-12-15',
        'hora_inicio': '09:00:00',
        'hora_fin': '09:30:00',
        'reservada': false,
        'requiere_confirmacion': true,
      },
      <String, dynamic>{
        'tipo': 'citas_propias',
        'citas': <Object>[],
        'hay_mas': false,
      },
      <String, dynamic>{'tipo': 'clinica', 'nombre': 'Clínica'},
      <String, dynamic>{'tipo': 'navegacion', 'destino': 'catalogo'},
    ];

    expect(json.length, tipos.length);
    for (int i = 0; i < json.length; i++) {
      final TarjetaChatbot tarjeta = TarjetaChatbot.fromJson(json[i]);
      expect(tarjeta.tipo, tipos[i]);
    }
  });

  test(
    'propuesta conserva pendiente de confirmación y profesional opcional',
    () {
      final TarjetaPropuestaCita propuesta = TarjetaChatbot.fromJson(
        <String, dynamic>{
          'tipo': 'propuesta_cita',
          'oftalmologo_id': 4,
          'fecha': '2026-12-15',
          'hora_inicio': '09:00:00',
          'hora_fin': '09:30:00',
          'reservada': false,
          'requiere_confirmacion': true,
          'profesional': <String, dynamic>{
            'id': 4,
            'nombre': 'Profesional Ficticio',
            'especialidad': null,
          },
        },
      ) as TarjetaPropuestaCita;

      expect(propuesta.reservada, isFalse);
      expect(propuesta.requiereConfirmacion, isTrue);
      expect(propuesta.horaInicioCorta, '09:00');
      expect(propuesta.horaFinCorta, '09:30');
      expect(propuesta.profesional?.nombre, 'Profesional Ficticio');
      expect(propuesta.profesional?.especialidad, isNull);
      expect(propuesta.fecha, DateTime(2026, 12, 15));
    },
  );

  test('disponibilidad sin profesional/franja no inventa datos', () {
    final TarjetaDisponibilidad d = TarjetaChatbot.fromJson(<String, dynamic>{
      'tipo': 'disponibilidad',
      'oftalmologo_id': 2,
      'fecha': '2026-12-15',
      'intervalos': <Object>[
        <String, dynamic>{'hora_inicio': '08:00:00', 'hora_fin': '08:30:00'},
      ],
    }) as TarjetaDisponibilidad;

    expect(d.profesional, isNull);
    expect(d.franja, FranjaChat.desconocida);
    expect(d.intervalos.single.inicioCorto, '08:00');
    expect(d.intervalos.single.etiqueta, '08:00 – 08:30');
  });

  test('citas propias y navegación son privadas', () {
    final TarjetaCitasPropias citas = TarjetaChatbot.fromJson(<String, dynamic>{
      'tipo': 'citas_propias',
      'citas': <Object>[
        <String, dynamic>{
          'id': 9,
          'oftalmologo_id': 3,
          'fecha': '2026-12-15',
          'hora_inicio': '10:00:00',
          'hora_fin': '10:30:00',
          'estado': 'PROGRAMADA',
        },
      ],
      'hay_mas': true,
    }) as TarjetaCitasPropias;
    expect(citas.esPrivada, isTrue);
    expect(citas.hayMas, isTrue);
    expect(citas.citas.single.franja, '10:00 – 10:30');

    final TarjetaNavegacion nav = TarjetaChatbot.fromJson(<String, dynamic>{
      'tipo': 'navegacion',
      'destino': 'cancelar_cita',
      'cita_id': 9,
    }) as TarjetaNavegacion;
    expect(nav.esPrivada, isTrue);
    expect(nav.destino, DestinoChat.cancelarCita);
    expect(nav.accionDisponible, isTrue);

    final TarjetaNavegacion sinId = TarjetaChatbot.fromJson(<String, dynamic>{
      'tipo': 'navegacion',
      'destino': 'detalle_cita',
    }) as TarjetaNavegacion;
    expect(sinId.accionDisponible, isFalse);
    expect(sinId.destino.requiereCitaPropia, isTrue);
  });

  test('clínica solo conserva campos existentes', () {
    final TarjetaClinica clinica = TarjetaChatbot.fromJson(<String, dynamic>{
      'tipo': 'clinica',
      'nombre': 'Clínica Ficticia',
      'telefono': null,
      'correo': null,
      'direccion': 'Calle 1',
      'horario_general': null,
    }) as TarjetaClinica;
    expect(clinica.nombre, 'Clínica Ficticia');
    expect(clinica.direccion, 'Calle 1');
    expect(clinica.telefono, isNull);
    expect(clinica.horarioGeneral, isNull);

    final TarjetaClinica vacia = TarjetaChatbot.fromJson(<String, dynamic>{
      'tipo': 'clinica',
    }) as TarjetaClinica;
    expect(vacia.sinDatos, isTrue);
  });

  test('discriminador desconocido y tipos inválidos no lanzan', () {
    final TarjetaChatbot desconocida = TarjetaChatbot.fromJson(
      <String, dynamic>{'tipo': 'inventada', 'extra': 1},
    );
    expect(desconocida, isA<TarjetaDesconocida>());

    final RespuestaChatbot respuesta = RespuestaChatbot.fromJson(
      <String, dynamic>{
        'conversacion_id': null,
        'respuesta': 123,
        'texto_voz': null,
        'tipo': 'tipo-nuevo',
        'tarjetas': 'no-es-lista',
      },
    );
    expect(respuesta.conversacionId, '');
    expect(respuesta.respuesta, '');
    expect(respuesta.tipo, TipoRespuestaChatbot.desconocido);
    expect(respuesta.tarjetas, isEmpty);
  });

  test('respuesta de orientación y privacidad se distinguen', () {
    for (final String tipo in <String>['orientacion', 'privacidad']) {
      final RespuestaChatbot respuesta = RespuestaChatbot.fromJson(
        <String, dynamic>{
          'conversacion_id': 'a',
          'respuesta': 'Texto',
          'tipo': tipo,
        },
      );
      expect(
        respuesta.tipo,
        tipo == 'orientacion'
            ? TipoRespuestaChatbot.orientacion
            : TipoRespuestaChatbot.privacidad,
      );
    }
  });

  test('respuesta privada se detecta por tipo o tarjeta', () {
    final RespuestaChatbot porTipo = RespuestaChatbot.fromJson(
      <String, dynamic>{
        'conversacion_id': 'a',
        'respuesta': 'Privacidad',
        'tipo': 'privacidad',
      },
    );
    expect(porTipo.contieneInformacionPrivada, isTrue);

    final RespuestaChatbot porTarjeta = RespuestaChatbot.fromJson(
      <String, dynamic>{
        'conversacion_id': 'a',
        'respuesta': 'Tus citas',
        'tipo': 'datos',
        'tarjetas': <Object>[
          <String, dynamic>{'tipo': 'citas_propias', 'citas': <Object>[]},
        ],
      },
    );
    expect(porTarjeta.contieneInformacionPrivada, isTrue);
  });

  test('fecha inválida no crea una fecha falsa', () {
    final TarjetaDisponibilidad d = TarjetaChatbot.fromJson(<String, dynamic>{
      'tipo': 'disponibilidad',
      'oftalmologo_id': 1,
      'fecha': 'no-es-fecha',
      'intervalos': <Object>[],
    }) as TarjetaDisponibilidad;
    expect(d.fecha, isNull);
  });
}
