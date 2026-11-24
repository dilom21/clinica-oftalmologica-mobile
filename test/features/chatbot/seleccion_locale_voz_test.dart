import 'package:flutter_test/flutter_test.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/services/voz/seleccion_locale_voz.dart';

void main() {
  group('selección de locales STT', () {
    test('declara variantes como candidatas, no como compatibles', () {
      expect(localesCandidatosEspanol, <String>[
        'es-BO',
        'es-419',
        'es-US',
        'es-MX',
        'es-ES',
      ]);
    });

    test('prioriza Bolivia y normaliza separadores', () {
      expect(
        ordenarLocalesEspanol(<String>['en-US', 'es_US', 'es_BO', 'es-MX']),
        <String>['es_BO', 'es_US', 'es-MX'],
      );
    });

    test('incluye variantes españolas disponibles cuando falta es-BO', () {
      expect(ordenarLocalesEspanol(<String>['en-US', 'es_US']), <String>[
        'es_US',
      ]);
      expect(ordenarLocalesEspanol(<String>['en-US']), isEmpty);
    });

    test(
      'soporte positivo se verifica y método no implementado bloquea',
      () async {
        expect(
          await comprobarSoporteLocalSeguro((_) async => true, 'es-US'),
          isTrue,
        );
        expect(
          await comprobarSoporteLocalSeguro((_) async => false, 'es-US'),
          isFalse,
        );
        expect(
          await seleccionarPrimerLocaleLocal(<String>[
            'es-BO',
            'es-US',
          ], (String locale) async => locale == 'es-US'),
          'es-US',
        );
        expect(
          await seleccionarPrimerLocaleLocal(<String>[
            'es-BO',
            'es-US',
          ], (_) => Future<bool>.error(UnsupportedError('not implemented'))),
          isNull,
        );
        expect(
          await comprobarSoporteLocalSeguro(
            (_) => Future<bool>.error(UnsupportedError('not implemented')),
            'es-US',
          ),
          isFalse,
        );
      },
    );
  });
}
