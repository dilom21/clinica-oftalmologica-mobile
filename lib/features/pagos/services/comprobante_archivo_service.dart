import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:printing/printing.dart';

/// Error legible al guardar/compartir el comprobante PDF.
class ComprobanteArchivoException implements Exception {
  const ComprobanteArchivoException(this.message);

  /// Mensaje entendible para mostrar al paciente.
  final String message;

  @override
  String toString() => message;
}

/// Guarda y comparte el comprobante PDF usando mecanismos del sistema.
///
/// - **Guardar:** abre el selector de documentos del sistema (en Android usa
///   Storage Access Framework), por lo que NO se solicitan permisos de
///   almacenamiento amplios.
/// - **Compartir:** usa el menú nativo (ACTION_SEND en Android) a partir de los
///   bytes del PDF; el plugin usa un archivo temporal privado propio (nunca se
///   expone una URL pública ni el JWT).
///
/// Para guardar, el PDF se escribe primero en un archivo temporal dentro de la
/// caché privada de la aplicación; ese fichero se reemplaza (no se acumulan
/// copias innecesarias).
///
/// Es inyectable en pruebas: las pruebas sustituyen los métodos que dependen de
/// plugins nativos para no invocarlos.
class ComprobanteArchivoService {
  const ComprobanteArchivoService();

  /// Subcarpeta privada donde se escriben los comprobantes temporales.
  static const String _carpetaTemporal = 'comprobantes';

  /// Escribe [bytes] en un archivo temporal privado y devuelve dicho archivo.
  Future<File> escribirTemporal(Uint8List bytes, String nombreArchivo) async {
    final String nombre = nombreArchivoSeguro(nombreArchivo);
    final Directory carpeta = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$_carpetaTemporal',
    );

    if (!await carpeta.exists()) {
      await carpeta.create(recursive: true);
    }

    final File archivo = File(
      '${carpeta.path}${Platform.pathSeparator}$nombre',
    );

    // Reemplaza cualquier copia previa del mismo comprobante.
    if (await archivo.exists()) {
      await archivo.delete();
    }

    await archivo.writeAsBytes(bytes, flush: true);
    return archivo;
  }

  /// Abre el selector del sistema para que el paciente guarde el PDF.
  ///
  /// Devuelve la ruta elegida o `null` si el paciente canceló el diálogo.
  Future<String?> guardarComo(Uint8List bytes, String nombreArchivo) async {
    try {
      final File temporal = await escribirTemporal(bytes, nombreArchivo);

      final String? ruta = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(sourceFilePath: temporal.path),
      );

      return ruta;
    } on ComprobanteArchivoException {
      rethrow;
    } on Exception {
      throw const ComprobanteArchivoException(
        'No se pudo guardar el comprobante en el dispositivo.',
      );
    }
  }

  /// Comparte el PDF mediante el menú nativo del teléfono.
  Future<void> compartir(Uint8List bytes, String nombreArchivo) async {
    try {
      await Printing.sharePdf(
        bytes: bytes,
        filename: nombreArchivoSeguro(nombreArchivo),
      );
    } on ComprobanteArchivoException {
      rethrow;
    } on Exception {
      throw const ComprobanteArchivoException(
        'No se pudo compartir el comprobante.',
      );
    }
  }

  /// Sanea el nombre del archivo y garantiza la extensión `.pdf`.
  static String nombreArchivoSeguro(String nombre) {
    final String limpio = nombre
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .trim();
    if (limpio.isEmpty) return 'comprobante_pago.pdf';
    return limpio.toLowerCase().endsWith('.pdf') ? limpio : '$limpio.pdf';
  }
}
