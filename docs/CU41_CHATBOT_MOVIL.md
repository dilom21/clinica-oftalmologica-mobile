# CU41 — Chatbot inteligente en la aplicación móvil

Documentación técnica de la implementación Flutter del **CU41: Interactuar con
chatbot inteligente**. El Backend es la única fuente de verdad de contratos,
reglas de negocio, herramientas y datos. Esta entrega no modifica el Backend.

- Repositorio: `clinica-oftalmologica-mobile`
- Rama: `dev-harold`
- Commit base: `abecc16324cb1661efd1dc32a4e04c279dae9268`
- Fecha: 21 de noviembre de 2026
- Estado: implementación y pruebas simuladas terminadas; validación en
  dispositivo físico y contra un Backend local autorizado pendiente.

---

## 1. Alcance

El asistente es **administrativo**. Permite:

- consultar servicios, precios y duración;
- consultar profesionales;
- consultar disponibilidad;
- preparar una propuesta de cita sin reservarla;
- consultar las citas propias;
- orientar la navegación a catálogo, agendamiento, mis citas, detalle,
  reprogramación y cancelación;
- consultar información institucional existente;
- conversar por texto o por voz con el mismo contexto.

No diagnostica, no prescribe, no interpreta exámenes, no ejecuta escrituras y
no sustituye al profesional de salud.

---

## 2. Arquitectura móvil

```
lib/features/chatbot/
├── controllers/
│   ├── chatbot_controller.dart      # conversación única, UUID, historial temporal
│   └── chat_voz_controller.dart     # máquina de estados de voz
├── models/
│   └── chatbot_models.dart          # contratos HTTP y 7 tarjetas + desconocidas
├── pages/
│   ├── chatbot_page.dart            # chat escrito (bienvenida + conversación)
│   ├── chat_voz_page.dart           # cuarta pantalla inmersiva
│   ├── chat_agendamiento_page.dart  # envoltura reutilizable de CU10
│   └── chat_citas_page.dart         # envoltura reutilizable de CU10
├── services/
│   ├── chatbot_service.dart         # HTTP + JWT + manejo de errores
│   └── voz/
│       ├── reconocimiento_voz.dart  # interfaz STT + adaptador speech_to_text
│       └── sintesis_voz.dart        # interfaz TTS + adaptador flutter_tts
└── widgets/
    ├── chatbot_ui.dart              # paleta, avatar robot, burbujas, avisos
    ├── chat_encabezado.dart         # encabezado del chat
    ├── chat_bienvenida.dart         # bienvenida y sugerencias
    ├── chat_conversacion.dart       # lista de mensajes y tarjetas
    ├── chat_compositor.dart         # campo, envío y acceso a voz
    ├── tarjetas_chatbot.dart        # dispatcher de tarjetas
    ├── tarjetas_chatbot_publicas.dart   # servicios/profesionales/horarios
    ├── tarjetas_chatbot_privadas.dart   # propuesta/citas/clínica/navegación
    ├── tarjeta_asistente_inicio.dart# tarjeta premium de Inicio
    └── esfera_voz.dart              # esfera con CustomPainter/animación
```

Piezas modificadas fuera del módulo:

- `lib/features/home/pages/inicio_page.dart`: tarjeta del asistente.
- `lib/features/home/pages/main_navigation_page.dart`: controlador compartido,
  apertura del chat/voz, invalidación al cerrar sesión y refresco de Inicio.
- `lib/features/citas/pages/agendar_cita_view.dart`: preselección opcional.
- `lib/features/citas/models/preseleccion_cita.dart`: objeto tipado de
  preselección (`oftalmologo_id`, fecha y hora de inicio).
- Configuración Android/iOS y dependencias STT/TTS.

Decisiones:

- `ChangeNotifier` + `AnimatedBuilder`, coherente con el resto de la app.
- Una sola conversación por área autenticada. Texto y voz usan el mismo
  `ChatbotController`, el mismo UUID y el mismo historial.
- Los adaptadores STT/TTS y la API HTTP son inyectables para pruebas.
- No se usa Bloc, Riverpod, GetX, SharedPreferences ni base local.

---

## 3. Contratos Backend utilizados

Autenticación: `Authorization: Bearer <JWT tenant>` leído de `TokenStorage`.
No se envían `empresa_id`, `tenant_id`, `paciente_id`, `historial` ni roles.

### Crear conversación

`POST {ApiConfig.baseUrl}/notificaciones-chatbot/conversaciones`

```json
{}
```

Respuesta `201`:

```json
{"conversacion_id":"UUID","expira_en_segundos":1800}
```

### Enviar mensaje

`POST /notificaciones-chatbot/conversaciones/{id}/mensajes`

```json
{"mensaje":"Texto del paciente","modalidad":"texto"}
```

`modalidad` es `texto` o `voz`. Respuesta `200`:

```json
{
  "conversacion_id":"UUID",
  "respuesta":"...",
  "texto_voz":"...",
  "tipo":"datos",
  "tarjetas":[]
}
```

`tipo` puede ser `texto`, `datos`, `orientacion` o `privacidad`. Tipos
desconocidos se conservan como `TipoRespuestaChatbot.desconocido` y no cierran
la app.

### Finalizar

`DELETE /notificaciones-chatbot/conversaciones/{id}` → `204` sin cuerpo.

### Tarjetas

Discriminadores implementados:

1. `servicios`
2. `profesionales`
3. `disponibilidad`
4. `propuesta_cita`
5. `citas_propias`
6. `clinica`
7. `navegacion`

Reglas de parseo relevantes:

- Los precios se conservan como **texto decimal exacto** (`"100.50"`); `null`
  no se convierte en cero y se muestra “Precio por consultar”.
- `hay_mas = null` significa completitud desconocida; no se anuncia como
  catálogo/lista completa.
- Las fechas inválidas quedan en `null`; no se inventa una fecha.
- Discriminadores desconocidos se muestran con una tarjeta neutra.
- `propuesta_cita` se presenta siempre como “Pendiente de confirmación”; nunca
  como reserva confirmada.
- `navegacion` se interpreta como intención, no como ruta ni ejecución.

---

## 4. Flujo conversacional y una única fuente de verdad

1. Abrir el chat **no** crea conversación ni solicita micrófono.
2. El UUID se crea en el primer mensaje enviado (texto o voz).
3. Cada mensaje reutiliza el UUID mientras no expire ni cambie la sesión.
4. `ChatbotController` mantiene en memoria:
   - UUID y expiración;
   - mensajes, respuestas y tarjetas;
   - modalidad utilizada;
   - estado de envío y error;
   - último mensaje reintentable;
   - generación de conversación.
5. Un solo envío simultáneo: `_enviando` se activa de forma síncrona antes de
   cualquier `await`.
6. `nuevaConversacion()` incrementa la generación, limpia el estado y hace un
   `DELETE` de mejor esfuerzo sobre el UUID anterior. El nuevo UUID se crea en
   el siguiente envío.
7. `finalizar()` hace `DELETE` y limpia todo.
8. TTL: se comprueba de forma perezosa al abrir/enviar. Al expirar se elimina
   UUID, mensajes y tarjetas y se muestra un aviso local.
9. Cambio de JWT: se detecta con una huella no reversible en memoria. Una
   respuesta emitida para otra sesión se descarta y el contexto se limpia.
10. Respuestas tardías: cada reinicio/cierre incrementa `generacion`; al volver
    del `await` se compara y se descarta lo obsoleto.
11. Un 404 descarta el UUID afectado y permite iniciar otra conversación sin
    afirmar que necesariamente expiró.
12. No se persiste historial ni se escriben transcripciones en logs.
13. Al cerrar sesión (logout, 401 o cambio de clínica):
    - se detiene STT y TTS desde el controlador de voz;
    - se invalidan solicitudes pendientes;
    - se eliminan mensajes, tarjetas y UUID;
    - los callbacks tardíos se descartan.

No se reenvían mensajes automáticamente. El botón **Reintentar** es explícito y
solo aparece cuando el error permite repetir sin duplicar el turno. En
timeout/desconexión el resultado es incierto y no se ofrece repetición
automática.

---

## 5. Pantallas y fidelidad visual

Paleta base tomada de `CitasColores` (#0D47A1, #1976D2, #4FC3F7, #F2F8FE,
#F4F9FF, #E1ECF5, #2E7D32, #C62828). El módulo añade variantes celestes y el
fondo nocturno `#071C38` para voz.

### 5.1 Inicio

- Tarjeta de ancho completo después de la próxima cita y antes de Acciones
  rápidas.
- Avatar robot original, degradado celeste, título “Asistente virtual”,
  descripción y botones **Conversar** / **Hablar**.
- No crea conversación ni inicializa el micrófono.
- Se conservan las cuatro pestañas y no se añade una quinta.

### 5.2 Chat inicial

- Encabezado con regreso, avatar, “Asistente virtual”, nombre real de la
  clínica autenticada y menú (nueva conversación, privacidad, voz).
- Bienvenida con avatar central, halo, saludo, descripción y cinco sugerencias.
- Aviso de alcance y enlace a privacidad.
- Compositor multilínea, límite de 1000 caracteres, envío y micrófono.
- Sin campana de notificaciones, adjuntos, cámara ni emojis.

### 5.3 Conversación activa

- Burbujas propias a la derecha con degradado azul; asistente a la izquierda con
  avatar, texto oscuro y acciones discretas (copiar y escuchar).
- Hora local opcional, desplazamiento automático solo si el paciente está cerca
  del final; si está leyendo mensajes anteriores se conserva la posición.
- Indicador de “escribiendo” discreto.
- Errores dentro de la conversación con acción explícita de reintento.
- No se simulan entregas, lectura, “en línea” ni streaming.

### 5.4 Asistente de voz

- Fondo degradado nocturno, encabezado minimalista, esfera luminosa, anillos,
  ondas, halo, estado y subtítulos.
- Transcripción parcial visible.
- Controles circulares: micrófono (pausar/continuar), detener respuesta,
  finalizar conversación (rojo) y volver al chat.
- Si hay tarjetas en la última respuesta, aparece “Ver respuesta y tarjeta(s)”,
  que vuelve al chat conservando la conversación.
- No se simula una llamada telefónica.

### 5.5 Evidencias visuales

Capturas reales renderizadas con Flutter (widgets reales, datos ficticios,
servicios simulados) en:

- `test/visual/goldens/cu41_01_inicio.png`
- `test/visual/goldens/cu41_02_chat_inicial.png`
- `test/visual/goldens/cu41_03_conversacion.png`
- `test/visual/goldens/cu41_04_voz.png`

Se generan/regeneran con un arnés golden que carga Roboto y Material Icons del
SDK de Flutter:

```powershell
flutter test --update-goldens --dart-define=CU41_GOLDEN=true test/visual/cu41_golden_test.dart
```

El arnés está **omitido** en la suite normal. No sustituye capturas en
dispositivo/emulador. En esta máquina no había emulador Android ni dispositivo
físico conectado (`flutter devices` solo mostró Windows y Edge). Las capturas
golden son evidencia de la composición del widget, no del motor real de voz.

---

## 6. Tarjetas dinámicas

- **servicios**: nombre, descripción, precio exacto en bolivianos, duración,
  “precio por consultar”, “duración no registrada”; acciones “Consultar” y
  “Ver catálogo completo”; aviso de más resultados/completitud desconocida.
- **profesionales**: nombre real, especialidad opcional, avatar genérico,
  “Disponibilidad” (consulta contextual al Backend).
- **disponibilidad**: profesional, fecha, franja, cuadrícula de horarios;
  seleccionar envía un mensaje con profesional + fecha + hora y conserva el
  UUID. Las tarjetas históricas muestran los horarios deshabilitados.
- **propuesta_cita**: superficie clara con acentos verdes, profesional, fecha,
  inicio/fin y “Pendiente de confirmación”. Botón “Continuar al agendamiento”.
  No incluye `servicio_id`.
- **citas_propias**: fecha, horario, profesional resuelto con CU09 cuando es
  posible, estado real con `ChipEstadoCita`, detalle con id válido, listas
  vacías y `hay_mas`.
- **clinica**: solo nombre, dirección, teléfono, correo y horario si existen.
  No se inventan FAQ ni políticas.
- **navegacion**: solo destinos permitidos. Las acciones destructivas abren el
  detalle CU10 y exigen confirmación; nunca se ejecutan desde la tarjeta.

---

## 7. Integración con CU09/CU10/CU38

### CU09

La tarjeta de disponibilidad y las tarjetas de citas usan datos del Backend.
Los nombres de profesionales de `citas_propias` se resuelven con
`GET /agenda-citas/oftalmologos` (información complementaria; si falla se
muestra “Profesional asignado”).

### CU10 — preselección mínima

`AgendarCitaView` acepta un `PreseleccionCita?`:

1. Carga los profesionales activos reales.
2. Resuelve el profesional por `oftalmologo_id`.
3. Aplica la fecha propuesta si no es pasada.
4. Consulta de nuevo `GET /agenda-citas/disponibilidad`.
5. Selecciona el horario solo si sigue disponible.
6. Informa si el profesional, la fecha o el horario dejaron de estar
   disponibles.
7. El paciente revisa, completa motivo/observaciones y confirma.
8. `paciente_id` se resuelve desde `GET /pacientes/me`.
9. En CU41 se vuelve a consultar disponibilidad justo antes de registrar y se
   comprueba otra vez el contexto de la propuesta tras los awaits. Solo entonces
   se registra mediante `POST /agenda-citas/citas` del flujo existente.
10. No se envía `servicio_id`. No se registra nada al recibir la propuesta.
11. El botón se bloquea durante el registro y se mantienen las protecciones
    existentes ante doble pulsación y timeout incierto.

Tras registrar, reprogramar o cancelar una cita, `ChatbotController.invalidarTarjetas()`
marca propuestas/disponibilidad anteriores como históricas y agrega un aviso
local. No se presenta una propuesta antigua como vigente.

### Vigencia de propuestas independiente del historial

La causa del fallo tras «Okay muchas gracias» era doble: `ChatConversacion`
permitía acciones solo en el último mensaje del asistente y el controlador
restablecía el indicador global de tarjetas tras cualquier respuesta correcta.
Ninguna de esas condiciones describe la vigencia de una propuesta.

Ahora el controlador mantiene **una única tarjeta pendiente**, referenciada por
el ID local de su mensaje y su índice en `tarjetas`. No se inventa un ID de
propuesta del Backend. Una propuesta nueva sustituye la anterior, aunque tenga
los mismos datos; dos opciones simultáneas no inventan una selección única.
Una tarjeta retirada nunca se recupera buscando hacia atrás en el historial.

El contrato actual solo incluye el sobre textual y las tarjetas; no comunica
si un turno cambió el contexto de agendamiento. La política local es conservadora:

- Se conserva la propuesta ante cortesías **completas y acotadas del paciente**
  como «Okay muchas gracias», «Perfecto, gracias» o «Entendido». No se compara ni
  clasifica el texto generado por DeepSeek para decidir vigencia.
- Cualquier otro mensaje aceptado retira la selección antes de consultar al
  Backend, incluso si falla la petición o la respuesta no trae tarjetas. Una
  mezcla como «gracias, pero cambia al 28» no es una cortesía pura.
- Los datos estructurados incompatibles, una cita real coincidente, una mutación
  de citas, cambio/cierre de sesión, cambio de conversación, TTL o inicio de la
  cita ya pasado la invalidan. Una respuesta anterior a una mutación de citas
  no puede instalar una propuesta basada en esa instantánea obsoleta.
- Enviar una cortesía suspende el botón temporalmente, sin marcar la propuesta
  como histórica. Un resultado de red incierto sí retira la propuesta.

Esta política favorece seguridad sobre comodidad: un mensaje inocuo que no sea
una cortesía reconocida puede requerir pedir una propuesta nueva. Para ampliar
el comportamiento de forma fiable, el **cambio mínimo de contrato propuesto** es
un efecto estructurado por turno (`efecto_propuesta: conservar | invalidar`),
producido por el estado/las herramientas del Backend, no por comparación del
texto del LLM. Una nueva `propuesta_cita` ya comunica la sustitución; no hace
falta inventar identificadores. Este campo es una propuesta de evolución:
**no se supone recibido ni se implementa ningún cambio del Backend**.

Antes de navegar se revalida la sesión/TTL y la identidad exacta de la tarjeta.
Se verifican ID positivo, fecha calendario válida, horas válidas y ordenadas,
y que siga siendo una propuesta no reservada que exige confirmación. El botón
abre `ChatAgendamientoPage` con `PreseleccionCita`; no reserva nada. La guarda
se conserva en el formulario para impedir confirmar si entretanto cambió la
conversación/propuesta. Las comprobaciones adicionales de CU41 son optativas en
`AgendarCitaView`: no se altera el comportamiento de otros accesos al CU10.

La disponibilidad se consulta al abrir el formulario y nuevamente al confirmar.
Si el turno ya no figura, no se hace POST. La operación de creación del Backend
sigue siendo la autoridad final ante una ocupación concurrente (409 sin
reintento automático). Volver/cancelar el formulario no crea una cita.

Las pruebas cubren la propuesta del 27/11/2026, 14:00–14:30, la cortesía posterior,
sustituciones, cambios de contexto sin tarjetas, invalidaciones y la navegación
real con preselección, cancelación y validación fresca. Esta mejora de vigencia
**requiere todavía validación física en el Redmi**. STT, TTS y la lógica social
del Backend no se modifican.

### CU38

“Ver catálogo completo” abre la `CatalogoPage` existente. “Consultar” sobre un
servicio envía una pregunta contextual al Backend. No se duplica el catálogo ni
su búsqueda/paginación.

---

## 8. Voz: STT, TTS y máquina de estados

### Dependencias

- `speech_to_text: ^7.5.0`
- `flutter_tts: ^4.2.5`
- `speech_to_text_platform_interface: ^2.5.0` (para comprobar
  `hasOnDeviceSupport`)

No se actualizaron las demás dependencias del proyecto.

### Estados

`inactivo`, `solicitandoPermiso`, `escuchando`, `procesando`, `respondiendo`,
`pausado`, `error`, `noDisponible`, `finalizado`.

### Ciclo automático (Nivel 2)

```
activar -> permiso -> escuchar -> fin de intervención -> detener STT ->
enviar (modalidad=voz) -> esperar JSON -> mostrar -> detener STT ->
TTS(texto_voz) -> finalización REAL de TTS -> volver a escuchar
```

- El mismo UUID se mantiene en todo el ciclo.
- STT y TTS nunca están activos a la vez.
- Se envían automáticamente finales nativos o parciales recuperables según la
  evidencia acústica existente. Los parciales inciertos requieren confirmación
  explícita; editar o mostrar su transcripción no envía una solicitud.
- Cada turno tiene identificador; callbacks de turnos anteriores se descartan.
- Tras 2 silencios o 2 errores consecutivos se pausa y se pide acción del
  paciente; no hay bucle infinito.
- Si la app pasa a segundo plano se detiene audio y se pausa. Al volver **no**
  se reactiva el micrófono sin una acción consciente.
- Salir de la pantalla de voz conserva la conversación. “Finalizar” ejecuta
  `DELETE` y borra el contexto.

### STT y privacidad local

Corrección de intervenciones truncadas: se eliminó la promoción del último
parcial a final a los 250 ms de `done`/`notListening`. También se configura
`SpeechToText.initialize(finalTimeout: Duration.zero)` para desactivar la
conversión equivalente dentro del plugin. Mientras la sesión está activa, los
parciales solo actualizan la pantalla. Se solicita `pauseFor=4s` y
`listenFor=45s`, con un límite de seguridad total de 47s. Android puede terminar
antes: estos parámetros no fuerzan al proveedor a prolongar su escucha.
Tras `done`, `notListening` o `error_no_match`, se esperan 2s por un final nativo.
Si `isListening` sigue activo se comprueba cada 500ms hasta 6s desde el cierre;
agotado ese plazo se solicita stop y se pausa sin recuperar. El cierre normal
solicita stop con un máximo de 3s y concede 500ms adicionales al final nativo.
Un final recibido durante esa espera tiene prioridad; una vez consumido el
turno, los eventos posteriores no pueden generar un segundo envío.

Sin final se permite una recuperación limitada únicamente tras cierre
notificado, stop completado y `isListening=false`: la hipótesis debe permanecer
sin cambios 1s y tener confianza explícita >=0.85 o haberse repetido al menos
dos veces. Si existe score entre 0 y 0.8 (excluidos valores ausentes), se exige
repetir; los valores 0/-1 no se interpretan como confianza alta. Una sola
hipótesis sin score y no corroborada también permite repetir, aunque sea larga.
Estas son señales de estabilidad, no una garantía semántica de completitud;
no se usa una longitud mínima. Ante `error_no_match` se preservan esas señales
y se evalúa la misma política después del cierre, sin cambiar de proveedor.
El límite global de 47s fuerza salida segura sin recuperación automática. Los
interrogativos aislados como «qué» se consideran incompletos incluso si son
finales; no se exige longitud mínima a otros finales, por ejemplo «Hola».
Resultados y temporizadores capturan la generación de turno; el controlador
revalida su turno después de detener STT y antes de enviar. Tras el fin TTS
confirmado se deja un margen de 450ms antes de abrir STT, revalidando pausa,
primer plano y generación. Este margen mitiga eco residual, pero su efectividad
y la segmentación del motor deben probarse físicamente en el Redmi.
Los diagnósticos propios registran clase de evento y turno, nunca palabras;
se desactiva el debug interno de STT para no depender de mensajes del proveedor.

Actualización de consentimiento: se prioriza el reconocedor on-device. Si
Android no lo ofrece, un segundo diálogo exige pulsar «Autorizo el servicio
general» antes de capturar audio. No hay autorización predeterminada ni
persistente; dura la sesión de la pantalla de voz. Rechazar conserva el chat
escrito. El servicio general puede transmitir audio a su proveedor y necesitar
Internet: no se presenta como offline. La app no guarda archivos de audio y
envía únicamente el texto aceptado (final nativo o recuperación validada) al chatbot con el UUID y modalidad `voz`
existentes. Los candidatos del modo general priorizan `es-US`; su aceptación
real depende del servicio, sin enumeración bloqueante de idiomas. No se cambia
de proveedor ante errores sin nueva autorización. Las protecciones TTS de
contenido privado siguen dependiendo exclusivamente del motor TTS verificado.

El adaptador real:

1. Inicializa el motor general y comprueba el permiso; no llama a
   `SpeechToText.locales()` durante preparación.
2. Trata `es_BO`, `es_419`, `es_US`, `es_MX`, `es_ES` como **candidatos**, no
   como locales anunciados o compatibles. No se consulta la lista de locales
   porque algunos servicios Android no responden a esa consulta.
3. Antes de abrir el micrófono comprueba por separado disponibilidad local. En
   Android consulta `isOnDeviceRecognitionAvailable` (API 31+); iOS consulta
   `hasOnDeviceSupport` del plugin.
4. Solo si esa comprobación es positiva, inicia `listen` con `onDevice: true`.
   El servicio debe aceptar el locale en la sesión; ante rechazo se prueba el
   siguiente candidato, sin enviar la transcripción al Backend.
5. Si falta motor general, permiso, soporte on-device o aceptación de locales,
   se informa la causa y se ofrece continuar por escrito. La modalidad general
   autorizada es la excepción explícita al requisito on-device descrito arriba.

Diagnóstico: `speech_to_text 7.5.0` no atendía
`has_on_device_support` en Android; el canal Dart devolvía `false` y bloqueaba
la captura, aunque hubiera reconocedor local. Se descartó `7.6.0-beta.4` porque
su APK falla al compilar Kotlin por declaraciones duplicadas en el plugin. La
app conserva 7.5.0 y usa un MethodChannel Android mínimo que consulta
`SpeechRecognizer.isOnDeviceRecognitionAvailable` (API 31+). Esta comprobación
indica disponibilidad del reconocedor local del dispositivo, **no** enumera
modelos descargados por idioma. En API 31 el locale solo se confirma si el
reconocedor local acepta la sesión; ante error de idioma se intenta la variante
siguiente. No se confía en la lista general de idiomas como prueba offline ni
se cae deliberadamente al servicio remoto. Los mensajes técnicos de desarrollo
excluyen audio, transcripciones y datos de sesión.

En el Redmi Note 9 Pro (Android 12/API 31) se comprobó: `initialize=true`,
permiso concedido, dos servicios generales visibles, pero
`onDeviceAvailable=false`. El listado `locales()` tardaba más de 8 segundos y
no demuestra compatibilidad local; se eliminó de la preparación y la
compatibilidad española queda **sin comprobar** mientras Android reporte
`onDeviceAvailable=false`. El servicio general solo se usa después del
consentimiento explícito de la sesión, tal como se describe arriba.

### TTS

Corrección del retorno automático a escucha: `_alTerminar()` del adaptador
guardaba mal el callback (lo borraba antes de invocarlo). Ahora captura `onFin`
antes de limpiar y el controlador consume cada terminal una sola vez. El
retorno de `speak()` con `awaitSpeakCompletion(false)` solo confirma aceptación;
únicamente `speak.onComplete` habilita el siguiente turno automático. Se
mantienen las guardas de sesión activa, pantalla visible, primer plano y pausa.
Cancelación o error solicitan stop y pausan; no se tratan como fin normal.
Un vigilante de 3 minutos para callback ausente solicita stop y reporta error:
no calcula cuándo acabó el audio ni reactiva el micrófono. Si stop falla o no
responde en 3 segundos, se conserva el bloqueo de audio activo y no se permite
abrir STT hasta confirmar una detención posterior. Las trazas de desarrollo
`[CU41Voice][TTS]` registran eventos e identificadores, nunca texto ni audio.
Las pruebas del adaptador real usan el canal simulado del plugin y no validan
audio físico; la verificación en Redmi de esta corrección sigue pendiente.

- Usa directamente `texto_voz`; no se reenvía a ningún LLM.
- Voz en español, velocidad 0.45, `awaitSpeakCompletion(false)` y callbacks de
  inicio/fin/error.
- La verificación de voz local depende de la plataforma:
  - En Android se consulta `isLanguageInstalled`, que exige una voz instalada
    sin dependencia de red.
  - En iOS y web no puede verificarse de forma fiable, por lo que
    `procesamientoLocalVerificado` es `false`.
- Si el motor local está verificado se puede leer también contenido privado; si
  no lo está:
  - se puede leer contenido público;
  - **no** se leen automáticamente respuestas `privacidad`, tarjetas
    `citas_propias` ni acciones de navegación privadas;
  - se informa que la información privada se muestra por escrito.
- Si no hay voz compatible, se informa y se continúa por escrito.

### STT compartido y reapertura de la pantalla

La inspección del código instalado de `speech_to_text 7.5.0` confirmó que
`SpeechToText()` es un singleton; `initialize` (líneas 313–319 del plugin)
retorna sin reemplazar listeners después del primer éxito. `listen`, en cambio,
reemplaza el listener de resultados. Crear un adaptador por pantalla enlazaba
resultados a la pantalla nueva y estados/errores a la primera, ya inactiva.

`_CoordinadorSpeech` conserva los listeners globales durante la aplicación y
despacha a un único propietario con generación de turno. Inicializaciones
concurrentes comparten un Future y el plugin no vuelve a inicializarse tras el
éxito; una inicialización fallida permite reintentar permisos. Los adaptadores
por pantalla conservan únicamente callbacks y consentimiento de esa sesión.
Cancelar revoca el consentimiento; liberar además elimina su callback y hace
inutilizable el adaptador. Detener para TTS conserva la autorización de la sesión.

Stop, cancel y listen pasan por una cola. La salida invalida callbacks y
temporizadores **antes** del await; una captura nueva espera las operaciones
anteriores, incluso si su llamador sufrió timeout. Si una operación nativa no
termina, no se abre otro micrófono por encima. Si falla el cierre, se bloquea
la siguiente captura hasta confirmar una liberación. La activación del
controlador también verifica su generación tras permisos y preparación TTS.

Las trazas `[CU41Voice][STTCoordinator]` incluyen adaptador destino, sesión,
generación, estado global nativo y si existe destinatario; nunca transcripciones.
Los resultados de callbacks anteriores se descartan por generación/propiedad.
La API del plugin no incluye identificadores nativos en estados/errores: estos
son globales y se despachan al propietario vigente, o se descartan durante la
liberación; no se pretende inferir un identificador que el proveedor no expone.

La regresión usa listeners fijados tras initialize: falla en la segunda pantalla
con el commit `4b942369` (esperado un final, recibido cero) y comprueba 21 aperturas
con el coordinador. Incluye recuperación de parciales, errores, final después
de done, exclusión de pantallas, liberación/stop pendientes, consentimiento,
pausa/finalización/segundo plano durante operaciones y tres turnos con TTS/UUID.
La prueba física reportada por el usuario del 23/11/2026 confirma el despacho
del coordinador en Redmi Note 9 Pro: estados del adaptador activo, recuperación,
envío, TTS, reactivación automática, varios turnos y reaperturas.

### Revisión de transcripciones inciertas

En esa prueba persistió otro caso: parciales entre 16:50:34–37, `notListening`
a las 16:50:41 y ausencia de final a las 16:50:43. La última hipótesis contenía
una fecha incompleta y no superaba la evidencia exigida para recuperación.

Ahora `intervencion_sin_final` con texto visual no vacío abre
`revisandoTranscripcion` dentro de la pantalla de voz. El paciente puede editar,
confirmar el texto exacto o repetir. No se completan ni deducen fechas, nombres
ni otros datos. Estabilidad/corroboración/confianza son evidencia **acústica**,
no una prueba de completitud semántica; se mantienen los umbrales y el envío
automático que ya funcionaban, sin añadir heurísticas lingüísticas.

El editor permanece deshabilitado hasta cancelar STT y comprobar el cierre
nativo. `cierreConfirmado` consulta el estado nativo y el bloqueo de cierre ya
existente: no basta `escuchando=false`, que también puede significar que el
adaptador dejó de ser propietario. El coordinador no cambia. La confirmación
consume el turno antes del primer await, vuelve a esperar el cierre y usa la
misma ruta de envío/TTS, modalidad voz y UUID. No hay otra sesión conversacional.
Repetir vuelve al flujo de escucha y consentimiento existente, sin enviar texto.

Cada editor está identificado por la generación de revisión. Pausar, salir,
ocultar la pantalla, segundo plano, finalizar o cambiar la conversación invalidan
la revisión. Al volver hay que repetir; una acción de un editor antiguo no puede
confirmar otro turno. El silencio mantiene sus reintentos/pausa sin editor vacío.
El editor es local al widget y se libera al desaparecer; no hay nuevo
almacenamiento de transcripciones ni cambios al chatbot escrito.

Las trazas sanitizadas de rechazo incluyen estabilidad, corroboración,
disponibilidad de confianza, bandas relativas a 0.8/0.85, permiso de recuperación,
notificación/confirmación de cierre y estado nativo. No incluyen palabras,
nombres, fechas, UUID ni puntuaciones ligadas a palabras.

Las pruebas reproducen la secuencia del Redmi sin final y comprueban edición,
confirmación, repetición, duplicados, UUID, callbacks antiguos, cierre pendiente
o fallido, cambio de conversación y ciclo de vida. La mejora de revisión manual
**todavía requiere validación física en el Redmi**.

### Esfera

- `CustomPainter` + `AnimationController` + `AnimatedBuilder` acotado.
- Refleja estado real: respiración, ondas con nivel de STT, anillos giratorios,
  halo azul, atenuación en pausa y estado de error.
- Respeta `MediaQuery.disableAnimations`.
- Libera el `AnimationController`.

---

## 9. Manejo de errores

| Situación | Comportamiento |
|---|---|
| 401 | Limpia conversación, detiene audio y reutiliza el cierre de sesión existente. |
| 403 | Informa falta de autorización; no muestra datos privados. |
| 404 | Descarta el UUID, conserva el historial visible y permite iniciar otra conversación. |
| 409 | Informa conversación ocupada; no hay solicitudes concurrentes. |
| 413/422 | Mensaje comprensible; se respeta el límite de 1000 caracteres. |
| 429 | Muestra el límite y `Retry-After`; no reintenta automáticamente. |
| 502/503/504 | Indisponibilidad temporal; interfaz estable y reintento explícito. |
| Timeout/red | No afirma que el servidor no procesó; no repite automáticamente; no ofrece reintento cuando el resultado es incierto. |
| Chatbot deshabilitado (503) | Se informa sin bloquear el resto de la app. |

El timeout móvil de mensajes es 65 s (el Backend usa 60 s por defecto), para no
abandonar solicitudes válidas. Crear/finalizar usan un timeout corto.

---

## 10. Permisos y configuración de plataforma

### Android

`android/app/src/main/AndroidManifest.xml`:

- `INTERNET` (existente, preservado).
- `RECORD_AUDIO`.
- `<queries>` para `android.speech.RecognitionService` y
  `android.intent.action.TTS_SERVICE`.
- No se añadieron ubicación, contactos, almacenamiento amplio ni Bluetooth.

`android/build.gradle.kts`: se excluye `flutter_tts` del override global de
Kotlin 17 porque el plugin declara Java/Kotlin 11. Sin esta exclusión Gradle
falla con “Inconsistent JVM Target Compatibility”. El APK debug compila.

### iOS

`ios/Runner/Info.plist`:

- `NSMicrophoneUsageDescription` en español.
- `NSSpeechRecognitionUsageDescription` en español.

No se añadieron modos de audio en segundo plano. La compilación iOS no se
ejecutó en Windows y **no se declara verificada**.

### API local

`ApiConfig.baseUrl` sigue configurable:

```powershell
flutter run --dart-define=API_URL=http://10.0.2.2:8000
```

- Emulador Android: `10.0.2.2` apunta al host.
- Dispositivo físico: usar la IP LAN del equipo que ejecuta FastAPI y que el
  firewall permita el puerto; no usar `localhost`.
- No se desactiva TLS ni se permite HTTP inseguro globalmente. Para pruebas
  locales, limitar cualquier excepción de red al entorno de desarrollo.
- No consumir DeepSeek real en pruebas móviles.

---

## 11. Privacidad

- El JWT se lee de `TokenStorage` y nunca se registra ni se guarda en la
  conversación.
- No se envían identidad, tenant, paciente ni historial en el body.
- El historial vive solo en memoria; no se usa almacenamiento local.
- No se guardan grabaciones, transcripciones, tarjetas privadas ni credenciales.
- El audio no se envía a DeepSeek.
- Antes de abrir el micrófono se muestra un consentimiento explícito con
  propósito, alcance administrativo y advertencia de no dictar contraseñas,
  documentos, datos de pago ni información clínica sensible.
- STT se restringe a reconocimiento local cuando puede comprobarse.
- TTS no lee información privada automáticamente salvo que el motor local se
  verifique; en ese caso se informa en la pantalla de voz.
- Las tarjetas privadas no se incluyen en logs ni telemetría. No se añadió SDK
  de analítica.

Riesgos residuales:

- Los motores nativos de STT/TTS pueden depender del sistema operativo y de
  paquetes de idioma instalados.
- En Android, la preferencia on-device puede no ser garantizable por el plugin.
- La detección de información sensible del Backend no es infalible.
- La voz real, la privacidad efectiva del motor y el comportamiento en
  llamadas/interrupciones requieren prueba en dispositivo.

---

## 12. Pruebas

Comandos ejecutados:

```powershell
flutter pub get
dart format <archivos modificados>
flutter analyze
flutter test
flutter build apk --debug
git diff --check
```

Resultados de esta intervención:

- `flutter analyze`: **No issues found**.
- Suite completa: **361 pruebas aprobadas, 4 omitidas, 0 fallos**.
  - Línea base anterior: 267 aprobadas.
  - Nuevas pruebas CU41: **94 aprobadas**.
  - 4 omitidas: arnés de capturas visuales (`CU41_GOLDEN`), no una reducción de
    cobertura funcional.
- APK debug: `build/app/outputs/flutter-apk/app-debug.apk` (≈205 MB, build
  debug). Compilación Android verificada; iOS no ejecutable en Windows.

Cobertura CU41:

- Modelos: 7 tarjetas, precios decimales/nulos, paginación, privacidad,
  discriminadores desconocidos, tipos inválidos, fechas inválidas.
- Servicio HTTP: URL, JWT, body exacto, texto/voz, 201/200/204, 401/403/404/409/
  413/422/429/502/503/504, timeout, JWT cambiado, JSON inválido, sin reintentos.
- Controlador: UUID único, historial compartido, concurrencia, duplicados,
  reintento explícito, 404, 401, nueva conversación, finalización, expiración,
  respuestas tardías, logout, invalidación de tarjetas.
- Voz: permiso denegado, sin motor local, parcial vs final, STT detenido antes
  de TTS, TTS terminado antes de reactivar, pausa, silencio, errores STT/TTS,
  segundo plano, ocultar pantalla, logout durante reproducción, contenido
  privado no leído, salir vs finalizar.
- Widgets: Inicio, bienvenida, sugerencias, compositor, burbujas, errores,
  tarjetas, históricas deshabilitadas, navegación, pantallas estrechas y texto
  al 200 %.
- CU10: preselección, consulta fresca, horario ocupado, profesional
  inexistente, confirmación explícita, `paciente_id` desde perfil, ausencia de
  registro automático, doble pulsación.

Las pruebas de voz usan adaptadores simulados. **No acreditan** STT/TTS reales
en un dispositivo físico.

Pruebas visuales (omitidas normalmente):

```powershell
flutter test --update-goldens --dart-define=CU41_GOLDEN=true test/visual/cu41_golden_test.dart
```

---

## 13. Integración local autorizada (procedimiento)

1. Levantar el Backend local con el CU41 habilitado (`CHATBOT_ENABLED=true` y
   una clave de proveedor autorizada en el entorno del Backend, nunca en
   Flutter). El chatbot está deshabilitado por defecto.
2. Preparar datos ficticios y un JWT de paciente de una clínica de prueba.
3. Iniciar la app apuntando a la URL local:
   - Emulador Android: `--dart-define=API_URL=http://10.0.2.2:<puerto>`.
   - Dispositivo físico: `--dart-define=API_URL=http://<IP_LAN>:<puerto>`.
4. Iniciar sesión con el paciente ficticio.
5. Abrir **Conversar** y probar:
   - sugerencias;
   - servicios/precios;
   - profesionales;
   - disponibilidad y selección de horario;
   - propuesta → formulario CU10 → confirmación manual.
6. Probar **Hablar** con el consentimiento, verificando:
   - que el micrófono se detiene antes de la respuesta;
   - que el TTS termina antes de volver a escuchar;
   - que no se activa al volver del segundo plano;
   - que no se lee información privada.
7. Probar 401, 404, 409, 429 y 503 con el Backend o un proxy de pruebas.
8. No usar la URL de AWS como sustituto de una integración local autorizada si
   aún no contiene el CU41.

No incluir secretos, JWT ni claves en capturas, logs o documentación.

---

## 14. Limitaciones conocidas

- Se verificó por ADB un Redmi Note 9 Pro, Android 12/API 31, y se instaló el
  APK con actualización conservando datos. No se inició una sesión de voz ni se
  validaron STT/TTS por interacción física; por tanto, el reconocimiento real
  todavía requiere prueba del usuario.
- La captura golden no valida micrófono, altavoz, permisos reales ni motores
  nativos.
- Android 31+ dispone de comprobación nativa del servicio on-device y la app
  evita escuchar cuando falta. La API 31 no permite consultar previamente la
  disponibilidad offline por idioma; la sesión local confirma cada variante y
  el motor puede rechazarla. Se conserva el bloqueo seguro si no acepta ninguna.
- En iOS/web no puede verificarse la localidad del motor TTS; en Android se usa
  `isLanguageInstalled` como comprobación, pero la política del motor instalado
  debe validarse en dispositivo.
- No hay streaming: el Backend devuelve un JSON completo.
- La conversación no se persiste; al expirar/cerrar se pierde.
- El TTL se comprueba de forma perezosa, sin temporizador en segundo plano.
- La compilación iOS no se ejecutó en Windows.
- Flutter advierte que `flutter_tts` y `flutter_file_dialog` aplican KGP
  (Kotlin Gradle Plugin). El APK actual compila, pero una versión futura de
  Flutter podría exigir una actualización de esos plugins.
- La integración con el Backend desplegado en AWS queda pendiente de una
  intervención autorizada; no se consumió DeepSeek real.

---

## 15. Criterios de aceptación cubiertos

- Inicio con acceso premium y cuatro pestañas conservadas.
- Chat inicial con bienvenida, sugerencias, aviso y compositor.
- Conversación con burbujas, carga, errores y tarjetas dinámicas.
- Voz inmersiva con esfera animada y estados reales.
- Texto y voz comparten UUID e historial.
- STT/TTS no se solapan; recursos liberados.
- Siete tarjetas implementadas.
- CU10 reutilizado con disponibilidad fresca y confirmación explícita.
- Navegación segura; operaciones destructivas con confirmaciones existentes.
- Privacidad, consentimiento y no persistencia.
- Accesibilidad: objetivos táctiles, semántica, tooltips, texto escalable,
  reducción de movimiento y alternativa escrita.
- `flutter analyze` limpio, 361 pruebas aprobadas y APK debug compilado.
- Evidencias visuales golden y limitaciones documentadas.

La aprobación funcional definitiva queda condicionada a la validación en
dispositivo físico y a la integración autorizada contra el Backend CU41.
