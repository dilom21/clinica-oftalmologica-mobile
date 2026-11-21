class ServicioCatalogo {
  const ServicioCatalogo({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.precio,
    this.duracion,
  });
  final int id;
  final String nombre;
  final String? descripcion;
  final double? precio;
  final int? duracion;
  factory ServicioCatalogo.fromJson(Map<String, dynamic> json) =>
      ServicioCatalogo(
        id: (json['id'] as num).toInt(),
        nombre: json['nombre'] as String,
        descripcion: json['descripcion'] as String?,
        precio: json['precio_base'] == null
            ? null
            : double.parse(json['precio_base'].toString()),
        duracion: (json['duracion_estimada'] as num?)?.toInt(),
      );
  String get precioTexto => precio == null
      ? 'Precio por consultar'
      : 'Precio: ${precio!.toStringAsFixed(2)}';
  String get duracionTexto =>
      duracion == null ? 'Duración por consultar' : '$duracion minutos';
}
