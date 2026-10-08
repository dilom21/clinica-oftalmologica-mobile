import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/storage/token_storage.dart';
import '../../authentication_security/pages/login/login_page.dart';
import '../services/comprobante_archivo_service.dart';
import '../services/pagos_service.dart';
import '../widgets/pagos_vistas.dart';

/// Construye el visor del PDF a partir de los [bytes] descargados.
typedef VisorComprobante = Widget Function(
  BuildContext context,
  Uint8List bytes,
  String nombreArchivo,
);

/// Visor por defecto: renderiza el PDF tal como lo generó FastAPI.
///
/// NO reconstruye ni recalcula el comprobante: únicamente muestra los bytes
/// recibidos del backend.
Widget visorComprobantePdf(
  BuildContext context,
  Uint8List bytes,
  String nombreArchivo,
) {
  return PdfPreview(
    build: (format) => Future<Uint8List>.value(bytes),
    allowPrinting: false,
    allowSharing: false,
    canChangePageFormat: false,
    canChangeOrientation: false,
  );
}

/// Pantalla dedicada para visualizar el comprobante de pago (PDF).
///
/// Descarga el PDF autenticado (solo lectura) y ofrece guardarlo con el
/// selector del sistema o compartirlo con el menú nativo del teléfono.
class ComprobantePagoPage extends StatefulWidget {
  const ComprobantePagoPage({
    super.key,
    required this.pagoId,
    this.pagosService,
    this.archivoService = const ComprobanteArchivoService(),
    this.visor = visorComprobantePdf,
  });

  /// Identificador del pago cuyo comprobante se va a mostrar.
  final int pagoId;

  /// Servicio HTTP de pagos; inyectable en pruebas.
  final PagosService? pagosService;

  /// Servicio de guardado/compartición; inyectable en pruebas.
  final ComprobanteArchivoService archivoService;

  /// Constructor del visor PDF; inyectable en pruebas.
  final VisorComprobante visor;

  @override
  State<ComprobantePagoPage> createState() => _ComprobantePagoPageState();
}

class _ComprobantePagoPageState extends State<ComprobantePagoPage> {
  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _azulPrincipal = Color(0xFF1976D2);

  late final PagosService _pagosService = widget.pagosService ?? PagosService();

  ComprobantePago? _comprobante;
  bool _cargando = true;
  String? _error;
  bool _guardando = false;
  bool _compartiendo = false;

  @override
  void initState() {
    super.initState();
    _descargar();
  }

  /// Descarga el PDF autenticado (operación de solo lectura).
  Future<void> _descargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final comprobante = await _pagosService.descargarComprobante(
        widget.pagoId,
      );

      if (!mounted) return;
      setState(() {
        _comprobante = comprobante;
        _cargando = false;
      });
    } on PagosException catch (error) {
      if (!mounted) return;

      // 401 = JWT inválido/expirado: limpiar sesión y volver al Login.
      if (error.statusCode == 401) {
        await _cerrarSesion();
        return;
      }

      setState(() {
        _error = error.message;
        _comprobante = null;
        _cargando = false;
      });
    }
  }

  Future<void> _cerrarSesion() async {
    await TokenStorage().deleteToken();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  /// Indica si hay una operación de archivo en curso.
  bool get _ocupado => _guardando || _compartiendo;

  /// Guarda el PDF con el selector del sistema (solo por acción del usuario).
  Future<void> _guardar() async {
    final comprobante = _comprobante;
    if (comprobante == null || _ocupado) return;

    setState(() {
      _guardando = true;
    });

    try {
      final ruta = await widget.archivoService.guardarComo(
        comprobante.bytes,
        comprobante.nombreArchivo,
      );

      if (!mounted) return;
      setState(() {
        _guardando = false;
      });
      _snack(
        ruta == null
            ? 'Guardado cancelado.'
            : 'Comprobante guardado correctamente.',
      );
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
      });
      _snack(_mensajeArchivo(error, 'No se pudo guardar el comprobante.'));
    }
  }

  /// Comparte el PDF con el menú nativo del teléfono.
  Future<void> _compartir() async {
    final comprobante = _comprobante;
    if (comprobante == null || _ocupado) return;

    setState(() {
      _compartiendo = true;
    });

    try {
      await widget.archivoService.compartir(
        comprobante.bytes,
        comprobante.nombreArchivo,
      );

      if (!mounted) return;
      setState(() {
        _compartiendo = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _compartiendo = false;
      });
      _snack(_mensajeArchivo(error, 'No se pudo compartir el comprobante.'));
    }
  }

  String _mensajeArchivo(Object error, String porDefecto) =>
      error is ComprobanteArchivoException ? error.message : porDefecto;

  void _snack(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _azulProfundo,
        elevation: 0,
        title: const Text('Comprobante de pago'),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: FondoPagos()),
          SafeArea(top: false, child: _cuerpo()),
        ],
      ),
      bottomNavigationBar: _comprobante == null ? null : _acciones(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: PagosCargando(mensaje: 'Obteniendo tu comprobante...'),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: PagosErrorVista(
          titulo: 'No se pudo mostrar el comprobante',
          mensaje: _error!,
          onReintentar: _descargar,
        ),
      );
    }

    return widget.visor(
      context,
      _comprobante!.bytes,
      _comprobante!.nombreArchivo,
    );
  }

  /// Barra inferior con las acciones explícitas de guardar y compartir.
  Widget _acciones() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D47A1).withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _ocupado ? null : _guardar,
                icon: _guardando
                    ? const _MiniProgreso(color: _azulPrincipal)
                    : const Icon(Icons.download_outlined),
                label: const Text('Guardar PDF'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _azulPrincipal,
                  side: const BorderSide(color: Color(0xFF9CC4E6)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _ocupado ? null : _compartir,
                icon: _compartiendo
                    ? const _MiniProgreso(color: Colors.white)
                    : const Icon(Icons.share_outlined),
                label: const Text('Compartir'),
                style: FilledButton.styleFrom(
                  backgroundColor: _azulPrincipal,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFB0C4D4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Indicador de progreso compacto para los botones de la barra inferior.
class _MiniProgreso extends StatelessWidget {
  const _MiniProgreso({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}
