import 'package:flutter/material.dart';

import '../../../core/storage/token_storage.dart';
import '../../authentication_security/pages/login/login_page.dart';
import '../models/informacion_clinica_models.dart';
import '../services/informacion_clinica_service.dart';
import 'consulta_clinica_detalle_page.dart';

/// CU25 - Consultar información clínica autorizada.
///
/// Muestra antecedentes, controles y consultas del paciente autenticado.
/// El detalle de cada consulta se abre con los datos ya recibidos: no hay
/// una segunda petición ni un identificador de otro paciente.
class InformacionClinicaPage extends StatefulWidget {
  const InformacionClinicaPage({
    super.key,
    this.servicio,
    this.alCerrarSesion,
  });

  final InformacionClinicaService? servicio;

  /// Se llama ante un JWT inválido. En producción borra la sesión y vuelve
  /// al login. Es inyectable para no depender del almacenamiento nativo.
  final Future<void> Function()? alCerrarSesion;

  @override
  State<InformacionClinicaPage> createState() => _InformacionClinicaPageState();
}

class _InformacionClinicaPageState extends State<InformacionClinicaPage> {
  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _azulPrincipal = Color(0xFF1976D2);
  static const Color _grisTexto = Color(0xFF5C6F80);

  late final InformacionClinicaService _servicio =
      widget.servicio ?? InformacionClinicaService();

  InformacionClinicaAutorizada? _informacion;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final informacion = await _servicio.consultar();
      if (!mounted) return;
      setState(() {
        _informacion = informacion;
        _cargando = false;
      });
    } on InformacionClinicaException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) {
        await _cerrarSesion();
        return;
      }
      setState(() {
        _error = error.message;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Ocurrió un error inesperado. Inténtalo de nuevo.';
        _cargando = false;
      });
    }
  }

  Future<void> _cerrarSesion() async {
    final cerrar = widget.alCerrarSesion;
    if (cerrar != null) {
      await cerrar();
      return;
    }

    await TokenStorage().deleteToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _abrirConsulta(ConsultaClinicaAutorizada consulta) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConsultaClinicaDetallePage(consulta: consulta),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _azulProfundo,
        elevation: 0,
        title: const Text(
          'Información clínica',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(
        key: Key('informacion-clinica-cargando'),
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return _EstadoMensaje(
        key: const Key('informacion-clinica-error'),
        icono: Icons.cloud_off_outlined,
        titulo: 'No se pudo consultar',
        mensaje: _error!,
        accion: 'Reintentar',
        onPressed: _cargar,
      );
    }

    final informacion = _informacion;
    if (informacion == null || informacion.estaVacia) {
      return const _EstadoMensaje(
        key: Key('informacion-clinica-vacia'),
        icono: Icons.medical_information_outlined,
        titulo: 'Sin información clínica',
        mensaje:
            'Todavía no hay información clínica autorizada para tu cuenta.',
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        key: const Key('informacion-clinica-contenido'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          if (informacion.fechaApertura != null ||
              informacion.observacionesGenerales != null)
            _Tarjeta(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _TituloSeccion('Tu historial'),
                  if (informacion.fechaApertura != null)
                    Text(
                      'Abierto el ${fechaClinica(informacion.fechaApertura)}',
                      style: const TextStyle(color: _grisTexto),
                    ),
                  if (informacion.observacionesGenerales != null) ...[
                    const SizedBox(height: 8),
                    Text(informacion.observacionesGenerales!),
                  ],
                ],
              ),
            ),
          if (informacion.antecedentes.isNotEmpty) ...[
            const _Encabezado('Antecedentes'),
            for (final antecedente in informacion.antecedentes)
              _Tarjeta(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      etiquetaTipoAntecedente(antecedente.tipo),
                      style: const TextStyle(
                        color: _azulPrincipal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(antecedente.descripcion),
                  ],
                ),
              ),
          ],
          if (informacion.controles.isNotEmpty) ...[
            const _Encabezado('Controles'),
            for (final control in informacion.controles)
              _Tarjeta(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            control.motivo ?? 'Control médico',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        _Chip(etiquetaEstadoControl(control.estado)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      fechaClinica(control.fechaProgramada),
                      style: const TextStyle(color: _grisTexto),
                    ),
                    Text(
                      control.oftalmologo.nombreCompleto,
                      style: const TextStyle(color: _grisTexto),
                    ),
                  ],
                ),
              ),
          ],
          if (informacion.consultas.isNotEmpty) ...[
            const _Encabezado('Consultas'),
            for (final consulta in informacion.consultas)
              _Tarjeta(
                onTap: () => _abrirConsulta(consulta),
                child: Column(
                  key: Key('consulta-clinica-${consulta.id}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      consulta.titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _azulProfundo,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fechaHoraClinica(consulta.fechaConsulta),
                      style: const TextStyle(color: _grisTexto),
                    ),
                    Text(
                      consulta.oftalmologo.nombreCompleto,
                      style: const TextStyle(color: _grisTexto),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ver detalle',
                      style: TextStyle(
                        color: _azulPrincipal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0D47A1),
        ),
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        texto,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF0D47A1),
        ),
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFD8ECFA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          color: Color(0xFF0D47A1),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EstadoMensaje extends StatelessWidget {
  const _EstadoMensaje({
    super.key,
    required this.icono,
    required this.titulo,
    required this.mensaje,
    this.accion,
    this.onPressed,
  });

  final IconData icono;
  final String titulo;
  final String mensaje;
  final String? accion;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 48, color: const Color(0xFF1976D2)),
            const SizedBox(height: 12),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0D47A1),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF5C6F80), height: 1.4),
            ),
            if (accion != null && onPressed != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onPressed, child: Text(accion!)),
            ],
          ],
        ),
      ),
    );
  }
}
