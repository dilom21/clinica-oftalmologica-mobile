class Notificacion {
  const Notificacion({
    required this.id,
    required this.titulo,
    required this.mensaje,
    required this.tipo,
    required this.fechaCreacion,
    required this.fechaEnvio,
    required this.leida,
    required this.fechaLectura,
  });

  final int id;
  final String titulo;
  final String mensaje;
  final String tipo;
  final DateTime? fechaCreacion;
  final DateTime? fechaEnvio;
  final bool leida;
  final DateTime? fechaLectura;

  factory Notificacion.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final titulo = json['titulo'];
    final mensaje = json['mensaje'];
    final tipo = json['tipo'];
    final leida = json['leida'];
    if (id is! int ||
        titulo is! String ||
        mensaje is! String ||
        tipo is! String ||
        leida is! bool) {
      throw const FormatException('Notificación inválida');
    }
    DateTime? fecha(Object? valor) =>
        valor is String ? DateTime.tryParse(valor) : null;
    return Notificacion(
      id: id,
      titulo: titulo,
      mensaje: mensaje,
      tipo: tipo,
      fechaCreacion: fecha(json['fecha_creacion']),
      fechaEnvio: fecha(json['fecha_envio']),
      leida: leida,
      fechaLectura: fecha(json['fecha_lectura']),
    );
  }
}

class PaginaNotificaciones {
  const PaginaNotificaciones({
    required this.items,
    required this.total,
    required this.limite,
    required this.desplazamiento,
  });

  final List<Notificacion> items;
  final int total;
  final int limite;
  final int desplazamiento;

  factory PaginaNotificaciones.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    final total = json['total'];
    final limite = json['limite'];
    final desplazamiento = json['desplazamiento'];
    if (items is! List ||
        total is! int ||
        limite is! int ||
        desplazamiento is! int ||
        total < 0 ||
        limite < 1 ||
        desplazamiento < 0) {
      throw const FormatException('Página de notificaciones inválida');
    }
    return PaginaNotificaciones(
      items: items.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Notificación inválida');
        }
        return Notificacion.fromJson(item);
      }).toList(),
      total: total,
      limite: limite,
      desplazamiento: desplazamiento,
    );
  }
}
