import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/features/authentication_security/models/auth_models.dart';

void main() {
  group('EmpresaTenant', () {
    test('lee codigo y nombre del JSON de FastAPI', () {
      final empresa = EmpresaTenant.fromJson(const {
        'codigo': 'CLN-A',
        'nombre': 'Visión Clara Norte',
      });

      expect(empresa.codigo, 'CLN-A');
      expect(empresa.nombre, 'Visión Clara Norte');
    });

    test('usa el código como nombre si el nombre viene vacío', () {
      final empresa = EmpresaTenant.fromJson(const {
        'codigo': 'CLN-A',
        'nombre': '  ',
      });

      expect(empresa.nombre, 'CLN-A');
    });

    test('compara clínicas por código', () {
      const a = EmpresaTenant(codigo: 'CLN-A', nombre: 'Visión Clara Norte');
      const b = EmpresaTenant(codigo: 'CLN-A', nombre: 'Otro nombre');
      const c = EmpresaTenant(codigo: 'CLN-B', nombre: 'Visión Clara Sur');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('LoginRequest', () {
    test('envía empresa_codigo, correo y password', () {
      const request = LoginRequest(
        empresaCodigo: 'CLN-A',
        correo: 'paciente@correo.com',
        password: 'clave',
      );

      expect(request.toJson(), {
        'empresa_codigo': 'CLN-A',
        'correo': 'paciente@correo.com',
        'password': 'clave',
      });
    });
  });

  group('RegistroPacienteRequest', () {
    RegistroPacienteRequest request() {
      return RegistroPacienteRequest(
        empresaCodigo: 'CLN-A',
        ci: '12345678',
        nombres: 'Ana',
        apellidos: 'Pérez',
        fechaNacimiento: DateTime(1998, 7, 7),
        sexo: 'F',
        telefono: '70000000',
        contactoEmergencia: 'Familiar 71111111',
        direccion: 'Av. Ejemplo 123',
        correo: 'ana@correo.com',
        password: 'ClaveSegura123!',
      );
    }

    test('envía empresa_codigo junto a los datos del paciente', () {
      expect(request().toJson(), {
        'empresa_codigo': 'CLN-A',
        'ci': '12345678',
        'nombres': 'Ana',
        'apellidos': 'Pérez',
        'fecha_nacimiento': '1998-07-07',
        'sexo': 'F',
        'telefono': '70000000',
        'contacto_emergencia': 'Familiar 71111111',
        'direccion': 'Av. Ejemplo 123',
        'correo': 'ana@correo.com',
        'password': 'ClaveSegura123!',
      });
    });

    test('no envía tenant_id, database_name, rol_id ni usuario_id', () {
      final json = request().toJson();

      for (final prohibido in [
        'tenant_id',
        'database_name',
        'rol_id',
        'usuario_id',
      ]) {
        expect(json.containsKey(prohibido), isFalse, reason: prohibido);
      }
    });

    test('mantiene nulos los campos opcionales vacíos', () {
      final json = RegistroPacienteRequest(
        empresaCodigo: 'CLN-A',
        ci: '12345678',
        nombres: 'Ana',
        apellidos: 'Pérez',
        fechaNacimiento: DateTime(1998, 7, 7),
        sexo: 'F',
        telefono: '70000000',
        correo: 'ana@correo.com',
        password: 'ClaveSegura123!',
      ).toJson();

      expect(json['contacto_emergencia'], isNull);
      expect(json['direccion'], isNull);
    });
  });
}
