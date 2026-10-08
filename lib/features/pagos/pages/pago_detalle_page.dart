import 'package:flutter/material.dart';

import '../models/pago_models.dart';
import '../services/comprobante_archivo_service.dart';
import '../services/pagos_service.dart';
import '../widgets/estado_pago_chip.dart';
import '../widgets/pagos_vistas.dart';
import 'comprobante_pago_page.dart';

/// Detalle de un pago del historial: estado, datos, servicios pagados y acceso
/// al comprobante cuando el backend confirma el pago como APROBADO.
class PagoDetallePage extends StatelessWidget {
  const PagoDetallePage({
    super.key,
    required this.pago,
    this.pagosService,
    this.archivoService = const ComprobanteArchivoService(),
    this.visor = visorComprobantePdf,
  });

  /// Pago cuyo detalle se muestra.
  final PagoHistorial pago;

  /// Servicio HTTP de pagos; inyectable en pruebas.
  final PagosService? pagosService;

  /// Servicio de guardado/compartición; inyectable en pruebas.
  final ComprobanteArchivoService archivoService;

  /// Constructor del visor PDF; inyectable en pruebas.
  final VisorComprobante visor;

  /// Abre el comprobante SOLO si el backend confirma el pago APROBADO.
  Future<void> _abrirComprobante(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComprobantePagoPage(
          pagoId: pago.pagoId,
          pagosService: pagosService,
          archivoService: archivoService,
          visor: visor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0D47A1),
        elevation: 0,
        title: Text('Pago #${pago.pagoId}'),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: FondoPagos()),
          SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              children: [
                _ResumenPago(pago: pago),
                const SizedBox(height: 16),
                _ServiciosPago(pago: pago),
                const SizedBox(height: 20),
                if (pago.aprobado)
                  _BotonComprobante(onTap: () => _abrirComprobante(context))
                else
                  const _AvisoSinComprobante(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Contenedor blanco redondeado con la identidad visual del módulo Pagos.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.children, this.titulo, this.icono});

  final List<Widget> children;
  final String? titulo;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titulo != null) ...[
            Row(
              children: [
                if (icono != null) ...[
                  Icon(icono, size: 20, color: const Color(0xFF1976D2)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    titulo!,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0D47A1),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// Fila etiqueta/valor del detalle del pago.
class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              etiqueta,
              style: const TextStyle(fontSize: 13, color: Color(0xFF8A9BA9)),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF1B2B3A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resumen del pago: estado, fecha, importe, método y consulta asociada.
class _ResumenPago extends StatelessWidget {
  const _ResumenPago({required this.pago});

  final PagoHistorial pago;

  @override
  Widget build(BuildContext context) {
    final String? pasarela = pago.pasarela;

    return _Tarjeta(
      titulo: 'Pago #${pago.pagoId}',
      icono: Icons.receipt_long_outlined,
      children: [
        EstadoPagoChip(estado: pago.estadoPago),
        const SizedBox(height: 14),
        _Dato(
          etiqueta: 'Fecha',
          valor: formatearFechaHoraBolivia(pago.fechaMostrar),
        ),
        _Dato(
          etiqueta: 'Monto',
          valor: formatearMontoConMoneda(pago.moneda, pago.monto),
        ),
        _Dato(etiqueta: 'Moneda', valor: pago.moneda),
        _Dato(etiqueta: 'Método de pago', valor: pago.metodoPagoEtiqueta),
        if (pasarela != null && pasarela.trim().isNotEmpty)
          _Dato(etiqueta: 'Pasarela', valor: pasarela),
        if (pago.tieneConsulta)
          _Dato(etiqueta: 'Consulta', valor: '#${pago.consultaClinicaId}'),
      ],
    );
  }
}

/// Servicios realmente pagados con su importe aplicado y el total del backend.
class _ServiciosPago extends StatelessWidget {
  const _ServiciosPago({required this.pago});

  final PagoHistorial pago;

  @override
  Widget build(BuildContext context) {
    return _Tarjeta(
      titulo: 'Servicios pagados',
      icono: Icons.medical_services_outlined,
      children: [
        if (pago.servicios.isEmpty)
          const Text(
            'El pago no tiene servicios detallados.',
            style: TextStyle(color: Color(0xFF5C6F80)),
          )
        else
          for (final servicio in pago.servicios)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      servicio.nombreServicio,
                      style: const TextStyle(color: Color(0xFF1B2B3A)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatearMontoConMoneda(
                      pago.moneda,
                      servicio.montoAplicado,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0D47A1),
                    ),
                  ),
                ],
              ),
            ),
        const Divider(height: 22, color: Color(0xFFE4EDF4)),
        Row(
          children: [
            const Text(
              'Total',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF0D47A1),
              ),
            ),
            const Spacer(),
            Text(
              formatearMontoConMoneda(pago.moneda, pago.monto),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0D47A1),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Botón para abrir el comprobante de un pago APROBADO.
class _BotonComprobante extends StatelessWidget {
  const _BotonComprobante({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('Ver comprobante'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// Aviso cuando el pago todavía no está APROBADO (sin comprobante).
class _AvisoSinComprobante extends StatelessWidget {
  const _AvisoSinComprobante();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF3E5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0D7AE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline, color: Color(0xFFB26A00)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'El comprobante estará disponible cuando el pago figure como '
              'APROBADO en el servidor.',
              style: TextStyle(
                color: Color(0xFF8A4B00),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
