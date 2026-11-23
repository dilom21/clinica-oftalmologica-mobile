# Integración local Harold + Josias — Mobile

Fecha: 23 de noviembre de 2026. Repositorio `clinica-oftalmologica-mobile`.
Rama local de integración: `integracion-harold-josias`.
No se ejecutó `git push`, no se creó rama remota y no se modificó `dev-harold`.

## 1. Estado inicial

| Referencia | Hash |
|---|---|
| `dev-harold` local | `a034e05cee00049a6a235485374e75daf07349b9` |
| `origin/dev-harold` | `a034e05cee00049a6a235485374e75daf07349b9` |
| `origin/dev-josias` | `67b6ac197d15b4c4cc47bbdc63c585953017113a` |
| Base común | `59cd40e47a8258c15929db1700dadcbe6a4e81a0` |

`origin/dev-austin` y `origin/dev-quisbert` ya eran ancestros de `dev-harold` y de
`dev-josias`, por lo que no aportan contenido nuevo al integrar. `origin/dev-salet`
ya estaba en Harold y no se volvió a fusionar; `dev-jerez` no es ancestro de
Josias.

## 2. Integración y commits

- Rama creada desde `dev-harold`: `integracion-harold-josias`.
- Merge local `--no-ff --no-commit` de `origin/dev-josias`.
- Commit de merge: `b316c57` (`merge: integrar dev-josias en dev-harold (mobile push/analitica)`).
- Commit de compatibilidad: `49c94c8` (`test: adaptar navegacion CU41 a la pestana Avisos`).
- HEAD final: `49c94c8a02034341a00f8c44de4741fde6dfd32f`.
- `dev-harold` local y remoto permanecen en `a034e05`.
- `git merge-base --is-ancestor dev-harold HEAD` y
  `git merge-base --is-ancestor origin/dev-josias HEAD`: ambos código 0.

## 3. Funcionalidades incorporadas de Josias

- Notificaciones push con Firebase Core/Messaging, transporte FCM, coordinador,
  registro/revocación de dispositivo, bandeja in-app, preferencias y apertura de
  cita desde la notificación.
- Notificaciones locales Android/iOS (canal `clinica_push_channel`).
- Pantalla de Avisos dentro de la navegación del paciente.
- Módulo de analítica administrativa: modelos, servicio, exportación, gráfico y
  página (consume `/reportes/progresivos/*` e `/ia-predictiva/*`).
- Integración de inicialización push en `main.dart`, login/perfil y navegación.
- Configuración Android: google-services, permiso `POST_NOTIFICATIONS`, icono de
  notificación y cambio de paquete a `com.clinicaoftalmologica.mobile`.
- Configuración iOS: GoogleService-Info, AppDelegate y registro de plugins.
- Pruebas nuevas de analítica, notificaciones y coordinador push.

## 4. Conflictos y resolución

1. `pubspec.yaml`: Harold tenía `speech_to_text`, `flutter_tts` y
   `speech_to_text_platform_interface`; Josias añadía `firebase_core`,
   `firebase_messaging`, `crypto` y `flutter_local_notifications`.
   **Resolución:** se conservaron todas las dependencias.
2. `android/app/src/main/AndroidManifest.xml`: Harold añadía `RECORD_AUDIO` para
   CU41; Josias añadía `POST_NOTIFICATIONS`. **Resolución:** se conservaron ambos
   permisos. El resto del manifiesto y las queries de voz/TTS se mantuvieron.

No se usó `--ours`/`--theirs` de forma indiscriminada.

## 5. Compatibilidad y cambios adicionales

- La prueba CU41 `desde la barra inferior se abre el chat sin quinta pestaña`
  asumía 4 destinos. Josias añadió la pestaña **Avisos** (5 destinos).
  **Resolución:** se conserva el acceso al chat desde Inicio, se verifica que no
  exista un destino “Asistente” y se exige la barra
  `Inicio, Citas, Pagos, Avisos, Perfil`. No se eliminó ninguna pestaña.
- `flutter pub get` resolvió las dependencias y regeneró los registrantes nativos
  (sin cambios de contenido relevantes).
- Se conserva `--dart-define=API_URL` en `lib/core/config/api_config.dart`; la
  compilación se hizo con `--dart-define=API_URL=http://10.0.2.2:8000`.
- `_CoordinadorSpeech`, STT/TTS, consentimiento Android, recuperación de
  parciales, confirmación de transcripciones, prevención de duplicados y retorno
  al micrófono permanecen sin cambios funcionales.

## 6. Validación Mobile

| Ejecución | Resultado |
|---|---|
| `flutter pub get` | Correcto |
| `flutter analyze` | **No issues found** |
| `flutter test` | **497 aprobadas, 4 omitidas, 0 fallos** |
| `flutter build apk --debug --dart-define=API_URL=...` | **Correcto** |
| `git diff --check` | Correcto |

APK debug generada:

`C:\Users\Harold\Desktop\Clinic-Mobile\clinica-oftalmologica-mobile\build\app\outputs\flutter-apk\app-debug.apk`

Tamaño aproximado: 194 MB (debug). No se publicó ni se instaló en un dispositivo.

## 7. Compatibilidad Backend–Mobile revisada

- CU41: `/notificaciones-chatbot/conversaciones` y
  `/{id}/mensajes` existen en FastAPI; se conservan `conversacion_id`,
  `respuesta`, `texto_voz`, `tipo` y tarjetas.
- Push: `/notificaciones`, `/notificaciones/dispositivos`,
  `/notificaciones/dispositivos/{id}`, `/notificaciones/{id}/leida` y
  `/notificaciones/preferencias` coinciden en método y contrato. Los campos
  `token_fcm`, `plataforma` (`ANDROID`/`IOS`/`WEB`), `instalacion_id`,
  `app_version` y `nombre_dispositivo` coinciden; el backend no devuelve el token.
- Analítica: `/reportes/progresivos/*` e `/ia-predictiva/*` existen y los
  filtros/respuestas coinciden (`fecha_desde`, `fecha_hasta`, `granularidad`,
  `estado`, `indicador`, KPIs/series/exportación).
- La página de analítica **no está enlazada** desde la navegación de pacientes y
  el backend exige administrador + permiso “Generar reportes”. No se debe asumir
  que un JWT de paciente pueda abrirla; requiere un flujo/rol administrativo.
- La sesión de clínica y el JWT se conservan en `TokenStorage`; push usa el JWT
  tenant del paciente.
- No se inventaron credenciales Firebase: se incorporaron los archivos de
  configuración cliente que ya existían en `dev-josias`.

## 8. Riesgos y pendientes

- **Validación física pendiente:** el asistente de voz, la vigencia de propuestas
  y la navegación al formulario deben probarse en el Redmi Note 9 Pro. La APK
  compilada no demuestra funcionamiento físico.
- No se probó entrega push real (FCM), permiso de notificaciones en dispositivo,
  ni deep-link desde una notificación real.
- La página de analítica administrativa no está conectada a la navegación del
  paciente y requiere decisión de producto/rol.
- En pruebas de widgets aparece un aviso capturado
  `LateInitializationError` al inicializar notificaciones locales sin plugin
  nativo; no rompe la app, pero conviene revisar el orden de inicialización en
  dispositivo.
- iOS no se compiló en Windows.
- Los archivos `google-services.json` y `GoogleService-Info.plist` son
  configuración cliente de Firebase; revisar separación de entornos antes de
  publicar.
- No se modificó STT/TTS ni se reimplementó el asistente.

## 9. Comandos para levantar Mobile

```powershell
cd C:\Users\Harold\Desktop\Clinic-Mobile\clinica-oftalmologica-mobile
git switch integracion-harold-josias
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8000
flutter test
flutter build apk --debug --dart-define=API_URL=http://10.0.2.2:8000
```

## 10. Git final

- Rama actual: `integracion-harold-josias`.
- Sin upstream remoto; no existe `origin/integracion-harold-josias`.
- `git status` limpio.
- Sin push, sin PR y sin cambios en `dev-harold`.
