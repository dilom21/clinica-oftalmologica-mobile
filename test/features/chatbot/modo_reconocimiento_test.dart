import 'package:flutter_test/flutter_test.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/services/voz/reconocimiento_voz.dart';

void main() {
  test('prefiere local sin solicitar autorización general', () async {
    var consultas = 0;
    final modo = await seleccionarModoReconocimiento(
      localDisponible: true,
      solicitarConsentimientoGeneral: () async {
        consultas++;
        return true;
      },
    );
    expect(modo, ModoReconocimientoVoz.local);
    expect(consultas, 0);
  });

  test('general requiere aceptación afirmativa', () async {
    expect(
      await seleccionarModoReconocimiento(
        localDisponible: false,
        solicitarConsentimientoGeneral: () async => true,
      ),
      ModoReconocimientoVoz.generalAndroid,
    );
  });

  test('rechazar no selecciona ningún motor', () async {
    expect(
      await seleccionarModoReconocimiento(
        localDisponible: false,
        solicitarConsentimientoGeneral: () async => false,
      ),
      isNull,
    );
  });
}
