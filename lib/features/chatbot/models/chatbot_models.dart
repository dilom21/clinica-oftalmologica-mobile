// Modelos de CU41 - Interactuar con el chatbot inteligente.
//
// Corresponden EXACTAMENTE a los schemas de FastAPI documentados en
// `docs/CU41_BACKEND.md` y `schemas/chatbot.py`:
//
// - POST   /notificaciones-chatbot/conversaciones
// - POST   /notificaciones-chatbot/conversaciones/{id}/mensajes
// - DELETE /notificaciones-chatbot/conversaciones/{id}
//
// Reglas de tolerancia aplicadas en el parseo:
// - Ningún campo ausente o con tipo inesperado cierra la aplicación.
// - Los precios se conservan como texto decimal (el backend serializa
//   `Decimal` como string) y `null` NUNCA se convierte en cero.
// - Los discriminadores desconocidos se modelan como [TarjetaDesconocida] y la
//   interfaz los muestra de forma neutra, sin interpretar su contenido.
// - `hay_mas = null` significa "completitud desconocida", no `false`.

/// Modalidad aceptada por el backend al enviar un mensaje.
enum ModalidadChat {
  texto('texto'),
  voz('voz');

  const ModalidadChat(this.valorApi);

  /// Valor exacto del contrato (`texto` / `voz`).
  final String valorApi;
}

/// Tipos de respuesta del sobre del chatbot.
enum TipoRespuestaChatbot {
  texto('texto'),
  datos('datos'),
  orientacion('orientacion'),
  privacidad('privacidad'),

  /// Tipo no reconocido por esta versión de la app.
  desconocido('');

  const TipoRespuestaChatbot(this.valorApi);

  final String valorApi;

  static TipoRespuestaChatbot desdeApi(Object? valor) {
    final String texto = valor is String ? valor.trim().toLowerCase() : '';
    for (final TipoRespuestaChatbot tipo in TipoRespuestaChatbot.values) {
      if (tipo != TipoRespuestaChatbot.desconocido && tipo.valorApi == texto) {
        return tipo;
      }
    }
    return TipoRespuestaChatbot.desconocido;
  }
}

/// Respuesta de `POST /notificaciones-chatbot/conversaciones` (HTTP 201).
class ConversacionChatbot {
  const ConversacionChatbot({required this.id, required this.expiraEnSegundos});

  final String id;

  /// TTL de inactividad indicado por el backend (por defecto 1800 s).
  final int expiraEnSegundos;

  factory ConversacionChatbot.fromJson(Map<String, dynamic> json) {
    return ConversacionChatbot(
      id: _texto(json['conversacion_id']) ?? '',
      expiraEnSegundos: _entero(json['expira_en_segundos']) ?? 0,
    );
  }
}

/// Sobre de respuesta de un mensaje del chatbot.
class RespuestaChatbot {
  const RespuestaChatbot({
    required this.conversacionId,
    required this.respuesta,
    required this.textoVoz,
    required this.tipo,
    required this.tarjetas,
  });

  final String conversacionId;

  /// Respuesta textual ya fundamentada por el backend.
  final String respuesta;

  /// Texto preparado para síntesis de voz (sin Markdown).
  ///
  /// Si el backend no lo enviara, se usa [respuesta] como respaldo seguro.
  final String textoVoz;

  final TipoRespuestaChatbot tipo;
  final List<TarjetaChatbot> tarjetas;

  /// Indica si la respuesta contiene información privada que no debe leerse
  /// automáticamente con un motor TTS no verificado como local.
  bool get contieneInformacionPrivada {
    if (tipo == TipoRespuestaChatbot.privacidad) return true;
    return tarjetas.any((TarjetaChatbot tarjeta) => tarjeta.esPrivada);
  }

  factory RespuestaChatbot.fromJson(Map<String, dynamic> json) {
    final String respuesta = _texto(json['respuesta']) ?? '';
    final String? voz = _texto(json['texto_voz']);
    final Object? tarjetasJson = json['tarjetas'];

    return RespuestaChatbot(
      conversacionId: _texto(json['conversacion_id']) ?? '',
      respuesta: respuesta,
      textoVoz: voz == null || voz.isEmpty ? respuesta : voz,
      tipo: TipoRespuestaChatbot.desdeApi(json['tipo']),
      tarjetas: tarjetasJson is List
          ? <TarjetaChatbot>[
              for (final Object? item in tarjetasJson)
                if (item is Map<String, dynamic>) TarjetaChatbot.fromJson(item),
            ]
          : const <TarjetaChatbot>[],
    );
  }
}

/// Tarjeta dinámica discriminada por `tipo`.
sealed class TarjetaChatbot {
  const TarjetaChatbot();

  /// Discriminador original del backend.
  String get tipo;

  /// `privada` solo para citas propias y acciones de navegación privadas.
  bool get esPrivada => false;

  /// Construye la tarjeta correcta o una [TarjetaDesconocida] segura.
  factory TarjetaChatbot.fromJson(Map<String, dynamic> json) {
    final String tipo = _texto(json['tipo'])?.toLowerCase() ?? '';
    switch (tipo) {
      case 'servicios':
        return TarjetaServicios.fromJson(json);
      case 'profesionales':
        return TarjetaProfesionales.fromJson(json);
      case 'disponibilidad':
        return TarjetaDisponibilidad.fromJson(json);
      case 'propuesta_cita':
        return TarjetaPropuestaCita.fromJson(json);
      case 'citas_propias':
        return TarjetaCitasPropias.fromJson(json);
      case 'clinica':
        return TarjetaClinica.fromJson(json);
      case 'navegacion':
        return TarjetaNavegacion.fromJson(json);
      default:
        return TarjetaDesconocida(tipoRaw: tipo);
    }
  }
}

/// Servicio público del catálogo mostrado en una tarjeta.
class ServicioChat {
  const ServicioChat({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.precio,
    this.duracionMinutos,
  });

  final int? id;
  final String nombre;
  final String? descripcion;

  /// Precio decimal EXACTO tal como lo serializó FastAPI (`"100.50"`).
  ///
  /// `null` significa que el precio no está registrado; no es cero.
  final String? precio;

  final int? duracionMinutos;

  /// Precio listo para mostrar en bolivianos.
  String get precioTexto =>
      precio == null ? 'Precio por consultar' : 'Bs $precio';

  /// Duración lista para mostrar.
  String get duracionTexto => duracionMinutos == null
      ? 'Duración no registrada'
      : '$duracionMinutos min';

  factory ServicioChat.fromJson(Map<String, dynamic> json) {
    return ServicioChat(
      id: _entero(json['id']),
      nombre: _texto(json['nombre']) ?? 'Servicio sin nombre',
      descripcion: _texto(json['descripcion']),
      precio: _decimalComoTexto(json['precio']),
      duracionMinutos: _entero(json['duracion_minutos']),
    );
  }
}

/// Profesional público (nunca incluye credenciales ni fotografías).
class ProfesionalChat {
  const ProfesionalChat({
    required this.id,
    required this.nombre,
    this.especialidad,
  });

  final int? id;
  final String nombre;
  final String? especialidad;

  factory ProfesionalChat.fromJson(Map<String, dynamic> json) {
    return ProfesionalChat(
      id: _entero(json['id']),
      nombre: _texto(json['nombre']) ?? 'Profesional sin nombre',
      especialidad: _texto(json['especialidad']),
    );
  }
}

/// Intervalo horario devuelto por el backend (`HH:MM:SS`).
class IntervaloChat {
  const IntervaloChat({required this.horaInicio, required this.horaFin});

  final String horaInicio;
  final String horaFin;

  String get inicioCorto => _horaCorta(horaInicio);
  String get finCorto => _horaCorta(horaFin);
  String get etiqueta => '$inicioCorto – $finCorto';

  factory IntervaloChat.fromJson(Map<String, dynamic> json) {
    return IntervaloChat(
      horaInicio: _texto(json['hora_inicio']) ?? '',
      horaFin: _texto(json['hora_fin']) ?? '',
    );
  }
}

/// Franja de disponibilidad (`manana` / `tarde`).
enum FranjaChat {
  manana('manana', 'Mañana'),
  tarde('tarde', 'Tarde'),
  desconocida('', 'Franja no especificada');

  const FranjaChat(this.valorApi, this.etiqueta);

  final String valorApi;
  final String etiqueta;

  static FranjaChat desdeApi(Object? valor) {
    final String texto = valor is String ? valor.trim().toLowerCase() : '';
    if (texto == manana.valorApi) return manana;
    if (texto == tarde.valorApi) return tarde;
    return desconocida;
  }
}

/// Tarjeta `servicios`.
class TarjetaServicios extends TarjetaChatbot {
  const TarjetaServicios({
    required this.servicios,
    this.busqueda,
    this.offset,
    this.hayMas,
  });

  final List<ServicioChat> servicios;
  final String? busqueda;
  final int? offset;

  /// `null` = completitud desconocida (no equivale a `false`).
  final bool? hayMas;

  @override
  String get tipo => 'servicios';

  factory TarjetaServicios.fromJson(Map<String, dynamic> json) {
    return TarjetaServicios(
      servicios: _lista(json['servicios'], ServicioChat.fromJson),
      busqueda: _texto(json['busqueda']),
      offset: _entero(json['offset']),
      hayMas: _booleano(json['hay_mas']),
    );
  }
}

/// Tarjeta `profesionales`.
class TarjetaProfesionales extends TarjetaChatbot {
  const TarjetaProfesionales({
    required this.profesionales,
    this.hayMas,
    this.offset,
  });

  final List<ProfesionalChat> profesionales;

  /// `null` = completitud desconocida.
  final bool? hayMas;
  final int? offset;

  @override
  String get tipo => 'profesionales';

  factory TarjetaProfesionales.fromJson(Map<String, dynamic> json) {
    return TarjetaProfesionales(
      profesionales: _lista(json['profesionales'], ProfesionalChat.fromJson),
      hayMas: _booleano(json['hay_mas']),
      offset: _entero(json['offset']),
    );
  }
}

/// Tarjeta `disponibilidad`.
class TarjetaDisponibilidad extends TarjetaChatbot {
  const TarjetaDisponibilidad({
    required this.oftalmologoId,
    required this.fecha,
    required this.intervalos,
    this.profesional,
    this.franja = FranjaChat.desconocida,
  });

  final int? oftalmologoId;

  /// `null` si el backend no envió una fecha válida.
  final DateTime? fecha;

  final List<IntervaloChat> intervalos;
  final ProfesionalChat? profesional;
  final FranjaChat franja;

  @override
  String get tipo => 'disponibilidad';

  factory TarjetaDisponibilidad.fromJson(Map<String, dynamic> json) {
    return TarjetaDisponibilidad(
      oftalmologoId: _entero(json['oftalmologo_id']),
      fecha: _fecha(json['fecha']),
      intervalos: _lista(json['intervalos'], IntervaloChat.fromJson),
      profesional: _objeto(json['profesional'], ProfesionalChat.fromJson),
      franja: FranjaChat.desdeApi(json['franja']),
    );
  }
}

/// Tarjeta `propuesta_cita`.
///
/// El backend garantiza `reservada = false` y `requiere_confirmacion = true`.
/// La interfaz NUNCA debe presentarla como una cita confirmada.
class TarjetaPropuestaCita extends TarjetaChatbot {
  const TarjetaPropuestaCita({
    required this.oftalmologoId,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    this.profesional,
    this.reservada = false,
    this.requiereConfirmacion = true,
  });

  final int? oftalmologoId;
  final DateTime? fecha;
  final String horaInicio;
  final String horaFin;
  final ProfesionalChat? profesional;
  final bool reservada;
  final bool requiereConfirmacion;

  @override
  String get tipo => 'propuesta_cita';

  String get horaInicioCorta => _horaCorta(horaInicio);
  String get horaFinCorta => _horaCorta(horaFin);

  /// Datos del contrato, no una reserva ni garantía de disponibilidad.
  bool get datosValidos {
    final inicio = segundosHoraChat(horaInicio);
    final fin = segundosHoraChat(horaFin);
    return (oftalmologoId ?? 0) > 0 &&
        fecha != null &&
        inicio != null &&
        fin != null &&
        fin > inicio &&
        !reservada &&
        requiereConfirmacion &&
        (profesional?.id == null || profesional!.id == oftalmologoId);
  }

  DateTime? get inicioLocal {
    final segundos = segundosHoraChat(horaInicio);
    final dia = fecha;
    if (dia == null || segundos == null) return null;
    return DateTime(
      dia.year,
      dia.month,
      dia.day,
    ).add(Duration(seconds: segundos));
  }

  factory TarjetaPropuestaCita.fromJson(Map<String, dynamic> json) {
    return TarjetaPropuestaCita(
      oftalmologoId: _entero(json['oftalmologo_id']),
      fecha: _fechaPropuesta(json['fecha']),
      horaInicio: _texto(json['hora_inicio']) ?? '',
      horaFin: _texto(json['hora_fin']) ?? '',
      profesional: _objeto(json['profesional'], ProfesionalChat.fromJson),
      // Los literales del contrato son false/true; ante datos inválidos se
      // conserva el estado seguro (no reservada, requiere confirmación).
      reservada: _booleano(json['reservada']) ?? false,
      requiereConfirmacion: _booleano(json['requiere_confirmacion']) ?? true,
    );
  }
}

/// Cita propia mostrada en una tarjeta `citas_propias`.
class CitaPropiaChat {
  const CitaPropiaChat({
    required this.id,
    required this.oftalmologoId,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.estado,
  });

  final int? id;
  final int? oftalmologoId;
  final DateTime? fecha;
  final String horaInicio;
  final String horaFin;
  final String estado;

  String get horaInicioCorta => _horaCorta(horaInicio);
  String get horaFinCorta => _horaCorta(horaFin);
  String get franja => '$horaInicioCorta – $horaFinCorta';

  factory CitaPropiaChat.fromJson(Map<String, dynamic> json) {
    return CitaPropiaChat(
      id: _entero(json['id']),
      oftalmologoId: _entero(json['oftalmologo_id']),
      fecha: _fecha(json['fecha']),
      horaInicio: _texto(json['hora_inicio']) ?? '',
      horaFin: _texto(json['hora_fin']) ?? '',
      estado: (_texto(json['estado']) ?? '').toUpperCase(),
    );
  }
}

/// Tarjeta `citas_propias` (información privada).
class TarjetaCitasPropias extends TarjetaChatbot {
  const TarjetaCitasPropias({required this.citas, this.hayMas});

  final List<CitaPropiaChat> citas;

  /// `null` = completitud desconocida.
  final bool? hayMas;

  @override
  String get tipo => 'citas_propias';

  @override
  bool get esPrivada => true;

  factory TarjetaCitasPropias.fromJson(Map<String, dynamic> json) {
    return TarjetaCitasPropias(
      citas: _lista(json['citas'], CitaPropiaChat.fromJson),
      hayMas: _booleano(json['hay_mas']),
    );
  }
}

/// Tarjeta `clinica` (solo campos institucionales existentes).
class TarjetaClinica extends TarjetaChatbot {
  const TarjetaClinica({
    this.nombre,
    this.telefono,
    this.correo,
    this.direccion,
    this.horarioGeneral,
  });

  final String? nombre;
  final String? telefono;
  final String? correo;
  final String? direccion;
  final String? horarioGeneral;

  @override
  String get tipo => 'clinica';

  bool get sinDatos =>
      nombre == null &&
      telefono == null &&
      correo == null &&
      direccion == null &&
      horarioGeneral == null;

  factory TarjetaClinica.fromJson(Map<String, dynamic> json) {
    return TarjetaClinica(
      nombre: _texto(json['nombre']),
      telefono: _texto(json['telefono']),
      correo: _texto(json['correo']),
      direccion: _texto(json['direccion']),
      horarioGeneral: _texto(json['horario_general']),
    );
  }
}

/// Destinos de navegación permitidos por el backend.
enum DestinoChat {
  catalogo('catalogo', 'Ver catálogo de servicios'),
  agendarCita('agendar_cita', 'Ir a agendar una cita'),
  misCitas('mis_citas', 'Ver mis citas'),
  detalleCita('detalle_cita', 'Ver detalle de la cita'),
  reprogramarCita('reprogramar_cita', 'Reprogramar una cita'),
  cancelarCita('cancelar_cita', 'Gestionar una cancelación'),
  desconocido('', 'Acción no disponible');

  const DestinoChat(this.valorApi, this.etiqueta);

  final String valorApi;
  final String etiqueta;

  bool get requiereCitaPropia =>
      this == detalleCita || this == reprogramarCita || this == cancelarCita;

  static DestinoChat desdeApi(Object? valor) {
    final String texto = valor is String ? valor.trim() : '';
    for (final DestinoChat destino in DestinoChat.values) {
      if (destino != DestinoChat.desconocido && destino.valorApi == texto) {
        return destino;
      }
    }
    return DestinoChat.desconocido;
  }
}

/// Tarjeta `navegacion` (intención, nunca una ruta arbitraria).
class TarjetaNavegacion extends TarjetaChatbot {
  const TarjetaNavegacion({required this.destino, this.citaId});

  final DestinoChat destino;
  final int? citaId;

  @override
  String get tipo => 'navegacion';

  @override
  bool get esPrivada => true;

  bool get accionDisponible =>
      destino != DestinoChat.desconocido &&
      (!destino.requiereCitaPropia || (citaId ?? 0) > 0);

  factory TarjetaNavegacion.fromJson(Map<String, dynamic> json) {
    return TarjetaNavegacion(
      destino: DestinoChat.desdeApi(json['destino']),
      citaId: _entero(json['cita_id']),
    );
  }
}

/// Tarjeta con un discriminador no soportado por esta versión.
///
/// Se conserva para no perder la respuesta y se muestra de forma neutra.
class TarjetaDesconocida extends TarjetaChatbot {
  const TarjetaDesconocida({required this.tipoRaw});

  final String tipoRaw;

  @override
  String get tipo => tipoRaw;
}

/// Rol de un mensaje dentro de la conversación local (solo memoria).
enum RolMensajeChat { paciente, asistente, sistema }

/// Mensaje de la conversación temporal.
class MensajeChat {
  const MensajeChat({
    required this.id,
    required this.rol,
    required this.texto,
    required this.hora,
    this.tarjetas = const <TarjetaChatbot>[],
    this.tipo,
    this.textoVoz,
    this.esError = false,
    this.textoReintentable,
  });

  final String id;
  final RolMensajeChat rol;
  final String texto;
  final DateTime hora;
  final List<TarjetaChatbot> tarjetas;
  final TipoRespuestaChatbot? tipo;

  /// Texto exacto preparado por el backend para síntesis de voz.
  final String? textoVoz;

  /// `true` para el aviso local de un envío fallido.
  final bool esError;

  /// Texto del paciente que se puede reintentar de forma explícita.
  final String? textoReintentable;

  bool get tieneTarjetas => tarjetas.isNotEmpty;
}

// ---------------------------------------------------------------------------
// Utilidades de deserialización tolerantes
// ---------------------------------------------------------------------------

String? _texto(Object? valor) {
  if (valor is! String) return null;
  final String texto = valor.trim();
  return texto.isEmpty ? null : texto;
}

int? _entero(Object? valor) {
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  if (valor is String) return int.tryParse(valor.trim());
  return null;
}

bool? _booleano(Object? valor) {
  if (valor is bool) return valor;
  if (valor is String) {
    final String texto = valor.trim().toLowerCase();
    if (texto == 'true') return true;
    if (texto == 'false') return false;
  }
  return null;
}

/// Conserva el decimal exacto del backend sin pasar por `double`.
String? _decimalComoTexto(Object? valor) {
  if (valor == null) return null;
  if (valor is String) {
    final String texto = valor.trim();
    if (texto.isEmpty) return null;
    // Se rechazan textos arbitrarios: solo un decimal/entero simple.
    if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(texto)) return null;
    return texto;
  }
  if (valor is int) return valor.toString();
  if (valor is num) return valor.toString();
  return null;
}

DateTime? _fecha(Object? valor) {
  if (valor is! String) return null;
  final String texto = valor.trim();
  if (texto.isEmpty) return null;
  return DateTime.tryParse(texto);
}

DateTime? _fechaPropuesta(Object? valor) {
  if (valor is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(valor)) {
    return null;
  }
  final fecha = DateTime.tryParse(valor);
  if (fecha == null || fecha.toIso8601String().substring(0, 10) != valor) {
    return null; // DateTime normaliza, por ejemplo, un 30 de febrero.
  }
  return fecha;
}

/// Valida HH:mm[:ss] sin normalizar horas inexistentes.
int? segundosHoraChat(String valor) {
  if (!RegExp(r'^\d{2}:\d{2}(?::\d{2})?$').hasMatch(valor)) return null;
  final partes = valor.split(':').map(int.parse).toList();
  if (partes[0] > 23 ||
      partes[1] > 59 ||
      (partes.length == 3 && partes[2] > 59)) {
    return null;
  }
  return partes[0] * 3600 +
      partes[1] * 60 +
      (partes.length == 3 ? partes[2] : 0);
}

List<T> _lista<T>(Object? valor, T Function(Map<String, dynamic>) constructor) {
  if (valor is! List) return <T>[];
  return <T>[
    for (final Object? item in valor)
      if (item is Map<String, dynamic>) constructor(item),
  ];
}

T? _objeto<T>(Object? valor, T Function(Map<String, dynamic>) constructor) {
  if (valor is! Map<String, dynamic>) return null;
  return constructor(valor);
}

/// Convierte `HH:MM:SS` (u `HH:MM`) en `HH:mm` para mostrar.
String _horaCorta(String hora) {
  final List<String> partes = hora.trim().split(':');
  if (partes.length < 2) {
    return hora.trim().isEmpty ? '--:--' : hora.trim();
  }
  return '${partes[0].padLeft(2, '0')}:${partes[1].padLeft(2, '0')}';
}
