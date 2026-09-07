import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/features/citas/models/agenda_models.dart';

void main() {
  group('OftalmologoAgenda.fromJson', () {
    test('parsea un oftalmólogo con todos los campos', () {
      final oftalmologo = OftalmologoAgenda.fromJson(const {
        'id': 3,
        'matricula': 'MAT-123',
        'nombres': 'Ana',
        'apellidos': 'García',
        'especialidad': 'Oftalmología general',
      });

      expect(oftalmologo.id, 3);
      expect(oftalmologo.matricula, 'MAT-123');
      expect(oftalmologo.nombres, 'Ana');
      expect(oftalmologo.apellidos, 'García');
      expect(oftalmologo.especialidad, 'Oftalmología general');
      expect(oftalmologo.nombreCompleto, 'Ana García');
    });

    test('especialidad nula o vacía se conserva como null', () {
      final sinEspecialidad = OftalmologoAgenda.fromJson(const {
        'id': 1,
        'matricula': 'M1',
        'nombres': 'Luis',
        'apellidos': 'Pérez',
        'especialidad': null,
      });
      final especialidadVacia = OftalmologoAgenda.fromJson(const {
        'id': 2,
        'matricula': 'M2',
        'nombres': 'Luis',
        'apellidos': 'Pérez',
        'especialidad': '   ',
      });

      expect(sinEspecialidad.especialidad, isNull);
      expect(especialidadVacia.especialidad, isNull);
    });
  });

  group('IntervaloHorario.fromJson', () {
    test('parsea hora de inicio y hora de fin (HH:MM:SS)', () {
      final intervalo = IntervaloHorario.fromJson(const {
        'hora_inicio': '08:00:00',
        'hora_fin': '08:30:00',
      });

      expect(intervalo.horaInicio, '08:00:00');
      expect(intervalo.horaFin, '08:30:00');
    });
  });

  group('DisponibilidadRespuesta.fromJson', () {
    test('parsea una disponibilidad completa con horarios e intervalos', () {
      final respuesta = DisponibilidadRespuesta.fromJson(const {
        'oftalmologo': {
          'id': 5,
          'matricula': 'MAT-5',
          'nombres': 'Carlos',
          'apellidos': 'Ruiz',
          'especialidad': 'Retina',
        },
        'fecha': '2026-09-06',
        'tiene_horario': true,
        'horarios_base': [
          {'hora_inicio': '08:00:00', 'hora_fin': '17:00:00'},
        ],
        'intervalos_disponibles': [
          {'hora_inicio': '08:00:00', 'hora_fin': '08:30:00'},
          {'hora_inicio': '09:00:00', 'hora_fin': '10:00:00'},
        ],
      });

      expect(respuesta.oftalmologo.id, 5);
      expect(respuesta.oftalmologo.nombreCompleto, 'Carlos Ruiz');
      expect(respuesta.fecha, DateTime(2026, 9, 6));
      expect(respuesta.tieneHorario, isTrue);
      expect(respuesta.horariosBase, hasLength(1));
      expect(respuesta.intervalosDisponibles, hasLength(2));
      expect(respuesta.intervalosDisponibles[1].horaInicio, '09:00:00');
      expect(respuesta.intervalosDisponibles[1].horaFin, '10:00:00');
    });

    test('tiene_horario=false devuelve listas vacías', () {
      final respuesta = DisponibilidadRespuesta.fromJson(const {
        'oftalmologo': {
          'id': 5,
          'matricula': 'MAT-5',
          'nombres': 'Carlos',
          'apellidos': 'Ruiz',
        },
        'fecha': '2026-09-06',
        'tiene_horario': false,
      });

      expect(respuesta.tieneHorario, isFalse);
      expect(respuesta.horariosBase, isEmpty);
      expect(respuesta.intervalosDisponibles, isEmpty);
    });

    test('soporta números id como num y fecha ausente', () {
      final respuesta = DisponibilidadRespuesta.fromJson({
        'oftalmologo': {
          'id': 5.0,
          'matricula': 'MAT-5',
          'nombres': 'Carlos',
          'apellidos': 'Ruiz',
        },
      });

      expect(respuesta.oftalmologo.id, 5);
      expect(respuesta.tieneHorario, isFalse);
    });
  });
}
