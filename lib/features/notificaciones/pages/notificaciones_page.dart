import 'package:flutter/material.dart';

import '../../citas/pages/cita_detalle_page.dart';
import '../models/notificacion_models.dart';
import '../services/notificaciones_service.dart';

class NotificacionesPage extends StatefulWidget {
  const NotificacionesPage({super.key, this.service, this.onSesionInvalida});
  final NotificacionesService? service;
  final Future<void> Function()? onSesionInvalida;

  @override
  State<NotificacionesPage> createState() => NotificacionesPageState();
}

class NotificacionesPageState extends State<NotificacionesPage> {
  late final NotificacionesService _service =
      widget.service ?? NotificacionesService();
  List<NotificacionPaciente> _items = const [];
  PreferenciasNotificacion? _preferencias;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    refrescar();
  }

  Future<void> refrescar() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final resultados = await Future.wait<Object>([
        _service.listar(),
        _service.obtenerPreferencias(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = (resultados[0] as BandejaNotificaciones).items;
        _preferencias = resultados[1] as PreferenciasNotificacion;
        _cargando = false;
      });
    } on NotificacionesException catch (error) {
      if (error.statusCode == 401) {
        await widget.onSesionInvalida?.call();
        return;
      }
      if (mounted) {
        setState(() {
          _error = error.message;
          _cargando = false;
        });
      }
    }
  }

  Future<void> _abrir(NotificacionPaciente item) async {
    try {
      if (!item.leida) {
        await _service.marcarLeida(item.id);
      }
      final citaId = item.citaIdNavegable;
      if (!mounted) return;
      if (citaId != null) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => CitaDetallePage(
              citaId: citaId,
              onSesionInvalida: widget.onSesionInvalida,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notificación leída. No contiene una acción disponible.',
            ),
          ),
        );
      }
      await refrescar();
    } on NotificacionesException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _cambiar(String campo, bool valor) async {
    try {
      final preferencias = await _service.actualizarPreferencias({
        campo: valor,
      });
      if (mounted) {
        setState(() => _preferencias = preferencias);
      }
    } on NotificacionesException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notificaciones'),
      actions: [
        IconButton(
          onPressed: refrescar,
          icon: const Icon(Icons.refresh),
          tooltip: 'Actualizar',
        ),
      ],
    ),
    body: _cargando
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: refrescar,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: refrescar,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_preferencias != null)
                  ExpansionTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Preferencias'),
                    children: [
                      SwitchListTile(
                        title: const Text('Notificaciones push'),
                        value: _preferencias!.pushHabilitado,
                        onChanged: (v) => _cambiar('push_habilitado', v),
                      ),
                      SwitchListTile(
                        title: const Text('Recordatorios de citas'),
                        value: _preferencias!.recordatorios,
                        onChanged: (v) => _cambiar('recordatorios', v),
                      ),
                    ],
                  ),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: Text('No tienes notificaciones.')),
                  ),
                for (final item in _items)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        item.leida
                            ? Icons.notifications_none
                            : Icons.notifications_active,
                        color: item.leida
                            ? null
                            : Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        item.titulo,
                        style: TextStyle(
                          fontWeight: item.leida
                              ? FontWeight.normal
                              : FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        item.cuerpo,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: item.citaIdNavegable == null
                          ? null
                          : const Icon(Icons.chevron_right),
                      onTap: () => _abrir(item),
                    ),
                  ),
              ],
            ),
          ),
  );
}
