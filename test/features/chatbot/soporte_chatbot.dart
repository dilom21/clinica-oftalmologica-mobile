import 'dart:async';

import 'package:clinica_oftalmologica_mobile/features/chatbot/models/chatbot_models.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/services/chatbot_service.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/services/voz/reconocimiento_voz.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/services/voz/sintesis_voz.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/models/agenda_models.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/models/cita_models.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/services/agenda_service.dart';
import 'package:clinica_oftalmologica_mobile/features/perfil_paciente/models/mi_perfil_paciente.dart';
import 'package:clinica_oftalmologica_mobile/features/perfil_paciente/services/paciente_service.dart';

/// API simulada del chatbot. No realiza red real.
class ApiChatbotFalsa implements ChatbotApi {
  int crearLlamadas = 0;
  int enviarLlamadas = 0;
  int borrarLlamadas = 0;
  final List<String> idsBorrados = <String>[];
  final List<Map<String, Object?>> envios = <Map<String, Object?>>[];

  ChatbotException? errorCrear;
  ChatbotException? errorEnviar;
  ChatbotException? errorBorrar;

  String conversacionId = 'conv-1';
  int expiraEnSegundos = 1800;

  Future<RespuestaChatbot> Function(String mensaje, ModalidadChat modalidad)?
  alEnviar;

  RespuestaChatbot respuesta = const RespuestaChatbot(
    conversacionId: 'conv-1',
    respuesta: 'Respuesta de prueba',
    textoVoz: 'Respuesta de prueba',
    tipo: TipoRespuestaChatbot.texto,
    tarjetas: <TarjetaChatbot>[],
  );

  @override
  Future<ConversacionChatbot> crearConversacion() async {
    crearLlamadas++;
    if (errorCrear != null) throw errorCrear!;
    return ConversacionChatbot(
      id: conversacionId,
      expiraEnSegundos: expiraEnSegundos,
    );
  }

  @override
  Future<RespuestaChatbot> enviarMensaje({
    required String conversacionId,
    required String mensaje,
    required ModalidadChat modalidad,
  }) async {
    enviarLlamadas++;
    envios.add(<String, Object?>{
      'conversacion_id': conversacionId,
      'mensaje': mensaje,
      'modalidad': modalidad.valorApi,
    });
    if (errorEnviar != null) throw errorEnviar!;
    if (alEnviar != null) return alEnviar!(mensaje, modalidad);
    return respuesta;
  }

  @override
  Future<void> finalizarConversacion(String conversacionId) async {
    borrarLlamadas++;
    idsBorrados.add(conversacionId);
    if (errorBorrar != null) throw errorBorrar!;
  }
}

/// Reconocimiento de voz simulado con control manual de callbacks.
class SttFalso implements ReconocimientoVoz {
  EstadoPermisoVoz permiso = EstadoPermisoVoz.concedido;
  bool iniciarOk = true;
  bool local = true;
  String? locale = 'es_BO';

  int iniciarLlamadas = 0;
  int detenerLlamadas = 0;
  int cancelarLlamadas = 0;
  int liberarLlamadas = 0;
  bool _escuchando = false;

  /// Permite comprobar que el micrófono no arranca mientras TTS habla.
  bool Function()? consultarTts;
  bool? ttsHablandoAlIniciar;

  void Function(String)? _onParcial;
  void Function(String)? _onFinal;
  void Function(String)? _onError;
  void Function()? _onSilencio;

  @override
  bool get escuchando => _escuchando;

  @override
  bool get cierreConfirmado => !_escuchando;

  @override
  bool get procesamientoLocalVerificado => local && _escuchando;

  @override
  String? get localeUtilizado => locale;

  @override
  Future<bool> inicializar() async => true;

  @override
  Future<EstadoPermisoVoz> solicitarPermiso() async => permiso;

  @override
  Future<bool> iniciar({
    required void Function(String parcial) onParcial,
    required void Function(String texto) onFinal,
    required void Function(String error) onError,
    required void Function() onSilencio,
    void Function(double nivel)? onNivel,
  }) async {
    iniciarLlamadas++;
    ttsHablandoAlIniciar = consultarTts?.call();
    _onParcial = onParcial;
    _onFinal = onFinal;
    _onError = onError;
    _onSilencio = onSilencio;
    _escuchando = iniciarOk;
    return iniciarOk;
  }

  void parcial(String texto) => _onParcial?.call(texto);

  void final_(String texto) => _onFinal?.call(texto);

  void silencio() => _onSilencio?.call();

  void error(String error) => _onError?.call(error);

  @override
  Future<void> detener() async {
    detenerLlamadas++;
    _escuchando = false;
  }

  @override
  Future<void> cancelar() async {
    cancelarLlamadas++;
    _escuchando = false;
  }

  @override
  Future<void> liberar() async {
    liberarLlamadas++;
    _escuchando = false;
  }
}

/// Síntesis de voz simulada; la finalización se dispara manualmente.
class TtsFalso implements SintesisVoz {
  bool disponible = true;
  bool localVerificado = false;

  int hablarLlamadas = 0;
  int detenerLlamadas = 0;
  int liberarLlamadas = 0;
  final List<String> textos = <String>[];
  bool _hablando = false;

  /// Permite comprobar que TTS no arranca mientras STT escucha.
  bool Function()? consultarStt;
  bool? sttEscuchandoAlHablar;

  void Function()? _onFin;
  void Function(String)? _onError;

  @override
  bool get hablando => _hablando;

  @override
  bool get procesamientoLocalVerificado => localVerificado;

  @override
  Future<bool> inicializar() async => disponible;

  @override
  Future<void> hablar(
    String texto, {
    required void Function() onInicio,
    required void Function() onFin,
    required void Function(String error) onError,
  }) async {
    hablarLlamadas++;
    textos.add(texto);
    sttEscuchandoAlHablar = consultarStt?.call();
    _onFin = onFin;
    _onError = onError;
    if (!disponible) {
      onError('voz_no_disponible');
      return;
    }
    _hablando = true;
    onInicio();
  }

  void terminar() {
    if (!_hablando) return;
    _hablando = false;
    final void Function()? fin = _onFin;
    _onFin = null;
    fin?.call();
  }

  void fallar() {
    if (!_hablando) return;
    _hablando = false;
    final void Function(String)? error = _onError;
    _onError = null;
    error?.call('error_sintesis');
  }

  @override
  Future<void> detener() async {
    detenerLlamadas++;
    _hablando = false;
    _onFin = null;
    _onError = null;
  }

  @override
  Future<void> liberar() async {
    liberarLlamadas++;
    _hablando = false;
  }
}

/// Agenda simulada para CU09/CU10 sin red.
class AgendaFalsa extends AgendaService {
  AgendaFalsa({
    this.disponibilidad,
    this.errorDisponibilidad,
    this.oftalmologos = const <OftalmologoAgenda>[],
  });

  DisponibilidadRespuesta? disponibilidad;
  AgendaException? errorDisponibilidad;
  List<OftalmologoAgenda> oftalmologos;
  List<Cita> citas = const <Cita>[];

  int disponibilidadLlamadas = 0;
  int oftalmologosLlamadas = 0;
  int crearLlamadas = 0;
  int? ultimoOftalmologoId;
  DateTime? ultimaFecha;
  final List<CitaCreate> citasCreadas = <CitaCreate>[];
  Cita? citaCreada;
  AgendaException? errorCrear;

  @override
  Future<List<OftalmologoAgenda>> listarOftalmologos() async {
    oftalmologosLlamadas++;
    return oftalmologos;
  }

  @override
  Future<List<Cita>> listarCitas({String? estado}) async {
    return citas;
  }

  @override
  Future<DisponibilidadRespuesta> obtenerDisponibilidad({
    required int oftalmologoId,
    required DateTime fecha,
  }) async {
    disponibilidadLlamadas++;
    ultimoOftalmologoId = oftalmologoId;
    ultimaFecha = fecha;
    if (errorDisponibilidad != null) throw errorDisponibilidad!;
    return disponibilidad ??
        DisponibilidadRespuesta(
          oftalmologo: OftalmologoAgenda(
            id: oftalmologoId,
            matricula: 'MP-1',
            nombres: 'Profesional',
            apellidos: 'Ficticio',
          ),
          fecha: fecha,
          tieneHorario: true,
          horariosBase: const <IntervaloHorario>[],
          intervalosDisponibles: const <IntervaloHorario>[],
        );
  }

  @override
  Future<Cita> crearCita(CitaCreate cita) async {
    crearLlamadas++;
    citasCreadas.add(cita);
    if (errorCrear != null) throw errorCrear!;
    return citaCreada ??
        Cita(
          id: 10,
          pacienteId: cita.pacienteId,
          oftalmologoId: cita.oftalmologoId,
          fecha: cita.fecha,
          horaInicio: cita.horaInicio,
          horaFin: '09:30:00',
          estado: citaProgramada,
        );
  }
}

/// Paciente simulado con el `paciente_id` que exige CU10.
class PacienteFalso extends PacienteService {
  PacienteFalso({this.id = 7});

  final int id;
  int llamadas = 0;

  @override
  Future<MiPerfilPaciente> obtenerMiPerfil() async {
    llamadas++;
    return MiPerfilPaciente(
      id: id,
      correo: 'paciente@example.com',
      nombres: 'Paciente',
      apellidos: 'Ficticio',
      ci: '0000000',
      fechaNacimiento: DateTime(1990, 1, 1),
      sexo: 'F',
      estado: true,
    );
  }
}
