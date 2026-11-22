import 'dart:io';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:printing/printing.dart';

import 'analitica_service.dart';

class ExportacionAnaliticaService {
  const ExportacionAnaliticaService();

  Future<void> guardar(ArchivoExportado archivo) async {
    final nombre = nombreSeguro(archivo.nombre);
    if (archivo.mime.toLowerCase().contains('pdf')) {
      await Printing.sharePdf(bytes: archivo.bytes, filename: nombre);
      return;
    }
    final dir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}reportes_progresivos',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    final temporal = File('${dir.path}${Platform.pathSeparator}$nombre');
    await temporal.writeAsBytes(archivo.bytes, flush: true);
    await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(sourceFilePath: temporal.path),
    );
  }

  static String nombreSeguro(String value) {
    final limpio = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return limpio.isEmpty ? 'reporte' : limpio;
  }
}
