import 'package:flutter/material.dart';

import '../../../core/storage/token_storage.dart';
import '../../authentication_security/pages/login/login_page.dart';
import '../models/valoracion_models.dart';
import '../services/valoracion_service.dart';
import '../widgets/estrellas_selector.dart';
import '../widgets/valoraciones_vistas.dart';

/// Formulario de CU40 para registrar una nueva valoración o actualizar una
/// existente sobre una atención médica específica.
///
/// Cumple explícitamente:
/// - escala de 1 a 5 estrellas con validación;
/// - comentario opcional (hasta 1000 caracteres) + sugerencias rápidas;
/// - diálogo de confirmación antes de guardar o actualizar;
/// - mensaje informativo de error con opción de reintentar sin perder datos;
/// - cierre de sesión automático ante HTTP 401.
class ValorarAtencionPage extends StatefulWidget {
  const ValorarAtencionPage({
    super.key,
    required this.consultaClinicaId,
    required this.oftalmologo,
    required this.fechaConsulta,
    this.motivoConsulta,
    this.tieneReceta = false,
    this.empresaNombre,
    this.valoracionExistente,
    this.valoracionService,
  });

  final int consultaClinicaId;
  final OftalmologoValoracion oftalmologo;
  final DateTime fechaConsulta;
  final String? motivoConsulta;
  final bool tieneReceta;
  final String? empresaNombre;
  final ValoracionClinica? valoracionExistente;
  final ValoracionService? valoracionService;

  bool get esActualizacion => valoracionExistente != null;

  @override
  State<ValorarAtencionPage> createState() => _ValorarAtencionPageState();
}

class _ValorarAtencionPageState extends State<ValorarAtencionPage> {
  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _azulPrincipal = Color(0xFF1976D2);
  static const Color _grisTexto = Color(0xFF5C6F80);

  static const List<String> _sugerenciasRapidas = [
    'Excelente trato',
    'Explicación clara',
    'Puntualidad',
    'Buen seguimiento',
    'Instalaciones limpias',
  ];

  late final ValoracionService _service =
      widget.valoracionService ?? ValoracionService();

  late int _puntuacion;
  late final TextEditingController _comentarioController;

  bool _guardando = false;
  String? _errorValidacion;
  String? _errorEnvio;

  @override
  void initState() {
    super.initState();
    _puntuacion = widget.valoracionExistente?.puntuacion ?? 0;
    _comentarioController = TextEditingController(
      text: widget.valoracionExistente?.comentario ?? '',
    );
  }

  @override
  void dispose() {
    _comentarioController.dispose();
    super.dispose();
  }

  void _agregarSugerencia(String etiqueta) {
    if (_guardando) return;
    final actual = _comentarioController.text.trim();
    if (actual.toLowerCase().contains(etiqueta.toLowerCase())) {
      return;
    }
    final nuevoTexto = actual.isEmpty ? etiqueta : '$actual. $etiqueta';
    if (nuevoTexto.length <= comentarioMaxLongitudValoracion) {
      setState(() {
        _comentarioController.text = nuevoTexto;
        _comentarioController.selection = TextSelection.fromPosition(
          TextPosition(offset: nuevoTexto.length),
        );
      });
    }
  }

  /// Valida el formulario y pide confirmación explícita antes de enviar.
  Future<void> _solicitarConfirmacionYGuardar() async {
    if (_guardando) return;

    if (_puntuacion < puntuacionMinimaValoracion ||
        _puntuacion > puntuacionMaximaValoracion) {
      setState(() {
        _errorValidacion =
            'Debes seleccionar una puntuación entre $puntuacionMinimaValoracion y $puntuacionMaximaValoracion estrellas.';
      });
      return;
    }

    final comentario = _comentarioController.text.trim();
    if (comentario.length > comentarioMaxLongitudValoracion) {
      setState(() {
        _errorValidacion =
            'El comentario no puede superar los $comentarioMaxLongitudValoracion caracteres.';
      });
      return;
    }

    setState(() {
      _errorValidacion = null;
      _errorEnvio = null;
    });

    final esEdicion = widget.esActualizacion;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        icon: Icon(
          esEdicion ? Icons.edit_note_rounded : Icons.star_rounded,
          color: const Color(0xFFF59E0B),
          size: 42,
        ),
        title: Text(
          esEdicion ? '¿Confirmar actualización?' : '¿Confirmar valoración?',
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              esEdicion
                  ? 'Se actualizará tu valoración existente para la atención con Dr(a). ${widget.oftalmologo.nombreCompleto}.'
                  : 'Se registrará tu valoración para la atención con Dr(a). ${widget.oftalmologo.nombreCompleto}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _grisTexto, height: 1.4),
            ),
            const SizedBox(height: 14),
            EstrellasResumen(puntuacion: _puntuacion, tamano: 26),
            const SizedBox(height: 6),
            Text(
              '$_puntuacion / $puntuacionMaximaValoracion · ${etiquetaParaPuntuacion(_puntuacion)}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: _azulProfundo,
              ),
            ),
            if (comentario.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F9FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '“$comentario”',
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('btn_confirmar_dialogo_valoracion'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: _azulPrincipal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(esEdicion ? 'Actualizar' : 'Guardar'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;
    await _enviarValoracion();
  }

  /// Ejecuta POST (nueva) o PUT (actualizar) y maneja errores con reintento.
  Future<void> _enviarValoracion() async {
    setState(() {
      _guardando = true;
      _errorEnvio = null;
    });

    final comentario = _comentarioController.text.trim();

    try {
      final ValoracionClinica resultado;
      if (widget.esActualizacion) {
        resultado = await _service.actualizarValoracion(
          valoracionId: widget.valoracionExistente!.id,
          puntuacion: _puntuacion,
          comentario: comentario.isEmpty ? null : comentario,
        );
      } else {
        resultado = await _service.registrarValoracion(
          consultaClinicaId: widget.consultaClinicaId,
          puntuacion: _puntuacion,
          comentario: comentario.isEmpty ? null : comentario,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop<ValoracionClinica>(resultado);
    } on ValoracionException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) {
        await _cerrarSesionPorExpiracion();
        return;
      }
      setState(() {
        _guardando = false;
        _errorEnvio = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorEnvio =
            'Ocurrió un error inesperado al guardar tu valoración. Inténtalo nuevamente.';
      });
    }
  }

  Future<void> _cerrarSesionPorExpiracion() async {
    await TokenStorage().deleteToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final esEdicion = widget.esActualizacion;
    final clinica = widget.empresaNombre?.trim().isNotEmpty == true
        ? widget.empresaNombre!.trim()
        : 'Centro Oftalmológico';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          esEdicion ? 'Actualizar valoración' : 'Valorar atención',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: _azulProfundo,
          ),
        ),
        backgroundColor: const Color(0xFFF4F9FF),
        foregroundColor: _azulProfundo,
        elevation: 0,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: FondoValoraciones()),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Tarjeta resumen de la atención médica
                      _tarjeta(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFD6ECFA),
                                        Color(0xFFB7E3F9),
                                      ],
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.medical_services_outlined,
                                    color: _azulProfundo,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Dr(a). ${widget.oftalmologo.nombreCompleto}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF1B2B3A),
                                            ),
                                      ),
                                      if (widget.oftalmologo.especialidad
                                              ?.trim()
                                              .isNotEmpty ==
                                          true)
                                        Text(
                                          widget.oftalmologo.especialidad!
                                              .trim(),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: _grisTexto,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ValoracionEstadoChip(
                                  texto: clinica,
                                  color: _azulProfundo,
                                  fondo: const Color(0xFFF0F7FD),
                                  icono: Icons.local_hospital_outlined,
                                ),
                                ValoracionEstadoChip(
                                  texto: formatearFechaHoraValoracion(
                                    widget.fechaConsulta,
                                  ),
                                  color: _azulProfundo,
                                  fondo: const Color(0xFFF0F7FD),
                                  icono: Icons.event_available_outlined,
                                ),
                                if (widget.tieneReceta)
                                  const ValoracionEstadoChip(
                                    texto: 'Receta emitida',
                                    color: Color(0xFFB45309),
                                    fondo: Color(0xFFFFF8E1),
                                    icono: Icons.medication_outlined,
                                  ),
                              ],
                            ),
                            if (widget.motivoConsulta?.trim().isNotEmpty ==
                                true) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Motivo: ${widget.motivoConsulta!.trim()}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _grisTexto,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Tarjeta de calificación, sugerencias y comentario
                      _tarjeta(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              esEdicion
                                  ? 'Actualiza tu calificación'
                                  : '¿Cómo calificarías la atención recibida?',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: _azulProfundo,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Tu opinión nos ayuda a mejorar la calidad de nuestra clínica.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: _grisTexto),
                            ),
                            const SizedBox(height: 16),
                            EstrellasSelector(
                              puntuacion: _puntuacion,
                              habilitado: !_guardando,
                              onChanged: (valor) {
                                setState(() {
                                  _puntuacion = valor;
                                  _errorValidacion = null;
                                });
                              },
                            ),
                            if (_errorValidacion != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _errorValidacion!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],

                            const SizedBox(height: 20),

                            // Sugerencias rápidas opcionales
                            const Text(
                              'Aspectos a destacar (opcional)',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _grisTexto,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final etiqueta in _sugerenciasRapidas)
                                  ActionChip(
                                    label: Text(etiqueta),
                                    labelStyle: const TextStyle(
                                      fontSize: 12,
                                      color: _azulProfundo,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    backgroundColor: const Color(0xFFF0F7FD),
                                    side: const BorderSide(
                                      color: Color(0xFFD0E7F8),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    onPressed: _guardando
                                        ? null
                                        : () => _agregarSugerencia(etiqueta),
                                  ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            TextField(
                              key: const Key('campo_comentario_valoracion'),
                              controller: _comentarioController,
                              enabled: !_guardando,
                              minLines: 3,
                              maxLines: 5,
                              maxLength: comentarioMaxLongitudValoracion,
                              decoration: InputDecoration(
                                labelText: 'Comentario (opcional)',
                                hintText:
                                    'Cuéntanos cómo fue tu experiencia con el médico y la clínica...',
                                alignLabelWithHint: true,
                                filled: true,
                                fillColor: const Color(0xFFF8FBFF),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFC9DCEE),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFC9DCEE),
                                  ),
                                ),
                              ),
                            ),
                            if (_errorEnvio != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3E0),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFFFFCC80),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.error_outline,
                                          color: Color(0xFFE65100),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _errorEnvio!,
                                            style: const TextStyle(
                                              color: Color(0xFF9A3412),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      key: const Key(
                                        'btn_reintentar_valoracion',
                                      ),
                                      onPressed: _guardando
                                          ? null
                                          : _enviarValoracion,
                                      icon: const Icon(Icons.refresh, size: 18),
                                      label: const Text('Reintentar'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFFE65100,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFFE65100),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              key: const Key('btn_guardar_valoracion'),
                              onPressed: _guardando
                                  ? null
                                  : _solicitarConfirmacionYGuardar,
                              icon: _guardando
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      esEdicion
                                          ? Icons.save_as_outlined
                                          : Icons.send_rounded,
                                    ),
                              label: Text(
                                _guardando
                                    ? 'Guardando…'
                                    : (esEdicion
                                          ? 'Actualizar valoración'
                                          : 'Guardar valoración'),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: _azulPrincipal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: _azulPrincipal.withValues(alpha: 0.09),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}
