import 'package:flutter/material.dart';

import '../models/auth_models.dart';

/// Selector de clínica del login multitenant.
///
/// Solo pinta el estado que le entrega `LoginPage` (cargando, error, lista
/// vacía o listo); las peticiones HTTP viven en `AuthService`.
class ClinicaSelector extends StatelessWidget {
  const ClinicaSelector({
    super.key,
    required this.cargando,
    required this.error,
    required this.empresas,
    required this.seleccionada,
    required this.errorSeleccion,
    required this.habilitado,
    required this.onReintentar,
    required this.onAbrir,
  });

  /// Indica si se están cargando las clínicas.
  final bool cargando;

  /// Error de conexión al cargar las clínicas (null si no hubo).
  final String? error;

  /// Clínicas devueltas por FastAPI.
  final List<EmpresaTenant> empresas;

  /// Clínica elegida por el paciente.
  final EmpresaTenant? seleccionada;

  /// Error local cuando se intentó continuar sin clínica.
  final String? errorSeleccion;

  /// Permite abrir el selector (se deshabilita durante el login).
  final bool habilitado;

  /// Reintenta la carga de clínicas.
  final VoidCallback onReintentar;

  /// Abre la hoja inferior con las clínicas.
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return Container(
        key: const Key('login-clinicas-cargando'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300, width: 1.2),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Cargando clínicas disponibles…',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
      );
    }

    if (error != null) {
      return _AvisoClinicas(
        key: const Key('login-clinicas-error'),
        icono: Icons.cloud_off_outlined,
        titulo: 'No se pudieron cargar las clínicas',
        detalle: error!,
        color: const Color(0xFFC62828),
        fondo: const Color(0xFFFFF4F4),
        borde: const Color(0xFFF3C2C2),
        onReintentar: habilitado ? onReintentar : null,
      );
    }

    if (empresas.isEmpty) {
      return _AvisoClinicas(
        key: const Key('login-clinicas-vacio'),
        icono: Icons.location_city_outlined,
        titulo: 'No hay clínicas disponibles',
        detalle:
            'No encontramos clínicas habilitadas para iniciar sesión. '
            'Inténtalo de nuevo en unos minutos.',
        color: const Color(0xFF8A6D1F),
        fondo: const Color(0xFFFFF9E8),
        borde: const Color(0xFFF1E0B0),
        onReintentar: habilitado ? onReintentar : null,
      );
    }

    final bool hayError = errorSeleccion != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: const Key('login-clinica-selector'),
            onTap: habilitado ? onAbrir : null,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hayError
                      ? Theme.of(context).colorScheme.error
                      : seleccionada != null
                      ? const Color(0xFF1E88E5)
                      : Colors.grey.shade300,
                  width: hayError ? 1.4 : 1.2,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.business_outlined, color: Color(0xFF1976D2)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Clínica',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          seleccionada?.nombre ?? 'Selecciona tu clínica',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: seleccionada == null
                                ? FontWeight.w400
                                : FontWeight.w600,
                            color: seleccionada == null
                                ? const Color(0xFF8593A0)
                                : const Color(0xFF1A2B38),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.expand_more, color: Color(0xFF5C6F80)),
                ],
              ),
            ),
          ),
        ),
        if (hayError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              errorSeleccion!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Aviso de la sección de clínicas (error o lista vacía) con reintento.
class _AvisoClinicas extends StatelessWidget {
  const _AvisoClinicas({
    super.key,
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.color,
    required this.fondo,
    required this.borde,
    required this.onReintentar,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Color color;
  final Color fondo;
  final Color borde;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detalle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('login-clinicas-reintentar'),
                    onPressed: onReintentar,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reintentar'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1976D2),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hoja inferior para elegir una clínica de las devueltas por FastAPI.
class ClinicaSheet extends StatelessWidget {
  const ClinicaSheet({
    super.key,
    required this.empresas,
    required this.seleccionada,
  });

  final List<EmpresaTenant> empresas;
  final EmpresaTenant? seleccionada;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Text(
                'Selecciona tu clínica',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0D47A1),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                'Elige la clínica donde tienes tu cuenta de paciente.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: empresas.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final empresa = empresas[index];
                  final activa = empresa.codigo == seleccionada?.codigo;

                  return ListTile(
                    key: Key('login-clinica-opcion-${empresa.codigo}'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    tileColor: activa ? const Color(0xFFE3F2FD) : null,
                    leading: Icon(
                      Icons.local_hospital_outlined,
                      color: activa
                          ? const Color(0xFF1565C0)
                          : const Color(0xFF5C6F80),
                    ),
                    title: Text(
                      empresa.nombre,
                      style: TextStyle(
                        fontWeight: activa ? FontWeight.w700 : FontWeight.w500,
                        color: const Color(0xFF1A2B38),
                      ),
                    ),
                    trailing: activa
                        ? const Icon(
                            Icons.check_circle,
                            color: Color(0xFF1565C0),
                          )
                        : null,
                    onTap: () => Navigator.of(context).pop(empresa),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
