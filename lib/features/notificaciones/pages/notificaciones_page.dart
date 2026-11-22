import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import '../../citas/widgets/citas_ui.dart';
import '../models/notificacion.dart';
import '../services/notificaciones_service.dart';

class NotificacionesPage extends StatefulWidget {
  const NotificacionesPage({
    super.key,
    this.service,
    this.sesionClinica,
    this.onSesionInvalida,
  });

  final NotificacionesService? service;
  final SesionClinica? sesionClinica;
  final Future<void> Function()? onSesionInvalida;

  @override
  State<NotificacionesPage> createState() => _NotificacionesPageState();
}

class _NotificacionesPageState extends State<NotificacionesPage> {
  late final NotificacionesService _service =
      widget.service ?? NotificacionesService();
  final List<Notificacion> _items = [];
  final Set<int> _marcando = {};
  int _total = 0;
  int _desplazamiento = 0;
  int _version = 0;
  bool _cargando = false;
  bool _cargandoMas = false;
  String? _error;
  String? _codigoClinica;
  static const int _limite = 20;

  @override
  void initState() {
    super.initState();
    _codigoClinica = widget.sesionClinica?.clinica?.codigo;
    widget.sesionClinica?.addListener(_sesionCambio);
    _cargar();
  }

  @override
  void dispose() {
    _version++;
    widget.sesionClinica?.removeListener(_sesionCambio);
    super.dispose();
  }

  void _sesionCambio() {
    final nuevoCodigo = widget.sesionClinica?.clinica?.codigo;
    if (nuevoCodigo == _codigoClinica) return;
    _codigoClinica = nuevoCodigo;
    _version++;
    setState(() {
      _items.clear();
      _total = 0;
      _desplazamiento = 0;
      _error = null;
      _cargando = false;
      _cargandoMas = false;
      _marcando.clear();
    });
    if (nuevoCodigo != null) _cargar();
  }

  Future<void> _cargar({bool mas = false}) async {
    if (_cargando || _cargandoMas) return;
    final version = mas ? _version : ++_version;
    setState(() {
      if (mas) {
        _cargandoMas = true;
      } else {
        _items.clear();
        _total = 0;
        _desplazamiento = 0;
        _cargando = true;
      }
      _error = null;
    });
    try {
      final pagina = await _service.listar(
        limite: _limite,
        desplazamiento: mas ? _desplazamiento : 0,
      );
      if (!mounted || version != _version) return;
      setState(() {
        final ids = _items.map((item) => item.id).toSet();
        for (final item in pagina.items) {
          if (ids.add(item.id)) _items.add(item);
        }
        _desplazamiento += pagina.items.length;
        _total = pagina.items.isEmpty ? _desplazamiento : pagina.total;
      });
    } on SesionCambiadaException {
      if (!mounted || version != _version) return;
      setState(() {
        _items.clear();
        _total = 0;
        _desplazamiento = 0;
      });
    } on NotificacionesException catch (error) {
      if (!mounted || version != _version) return;
      if (error.statusCode == 401 && widget.onSesionInvalida != null) {
        await widget.onSesionInvalida!();
        return;
      }
      setState(() => _error = error.message);
    } finally {
      if (mounted && version == _version) {
        setState(() {
          _cargando = false;
          _cargandoMas = false;
        });
      }
    }
  }

  Future<void> _abrir(Notificacion item) async {
    if (_marcando.contains(item.id)) return;
    var actual = item;
    if (!item.leida) {
      setState(() => _marcando.add(item.id));
      final version = _version;
      try {
        actual = await _service.marcarLeida(item.id);
        if (!mounted || version != _version) return;
        final indice = _items.indexWhere((n) => n.id == item.id);
        if (indice >= 0) setState(() => _items[indice] = actual);
      } on SesionCambiadaException {
        if (mounted && version == _version) {
          setState(() {
            _items.clear();
            _total = 0;
            _desplazamiento = 0;
          });
        }
        return;
      } on NotificacionesException catch (error) {
        if (!mounted || version != _version) return;
        if (error.statusCode == 401 && widget.onSesionInvalida != null) {
          await widget.onSesionInvalida!();
          return;
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
        return;
      } finally {
        if (mounted && version == _version) {
          setState(() => _marcando.remove(item.id));
        }
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(actual.titulo),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_tipo(actual.tipo)),
              const SizedBox(height: 12),
              Text(actual.mensaje),
              if (actual.fechaCreacion != null) ...[
                const SizedBox(height: 12),
                Text('Creada: ${_fecha(actual.fechaCreacion)}'),
              ],
              if (actual.fechaEnvio != null)
                Text('Enviada: ${_fecha(actual.fechaEnvio)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  static String _tipo(String valor) => valor.replaceAll('_', ' ');

  static String _fecha(DateTime? valor) {
    if (valor == null) return '';
    final local = valor.toLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(local.day)}/${dos(local.month)}/${local.year} '
        '${dos(local.hour)}:${dos(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FF),
      appBar: AppBar(title: const Text('Notificaciones')),
      body: Stack(
        children: [
          const Positioned.fill(child: FondoCitas()),
          if (_cargando && _items.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_error != null && _items.isEmpty)
            _estado(_error!, accion: 'Reintentar', onPressed: _cargar)
          else if (_items.isEmpty)
            _estado('Aún no tienes notificaciones.')
          else
            RefreshIndicator(
              onRefresh: _cargar,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _items.length + 1,
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    if (_desplazamiento >= _total) {
                      return const SizedBox.shrink();
                    }
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _cargandoMas
                            ? const CircularProgressIndicator()
                            : TextButton(
                                onPressed: () => _cargar(mas: true),
                                child: Text(
                                  _error == null ? 'Cargar más' : 'Reintentar',
                                ),
                              ),
                      ),
                    );
                  }
                  final item = _items[index];
                  return Card(
                    key: Key('notificacion-${item.id}'),
                    color: item.leida ? Colors.white : const Color(0xFFE5F3FF),
                    child: ListTile(
                      onTap: () => _abrir(item),
                      leading: Icon(
                        item.leida
                            ? Icons.notifications_none
                            : Icons.notifications_active,
                        color: CitasColores.azulPrincipal,
                      ),
                      title: Text(
                        item.titulo,
                        style: TextStyle(
                          fontWeight: item.leida
                              ? FontWeight.normal
                              : FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.mensaje,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(_tipo(item.tipo)),
                          if (item.fechaCreacion != null)
                            Text(_fecha(item.fechaCreacion)),
                        ],
                      ),
                      trailing: _marcando.contains(item.id)
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _estado(String mensaje, {String? accion, VoidCallback? onPressed}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mensaje, textAlign: TextAlign.center),
          if (accion != null)
            TextButton(onPressed: onPressed, child: Text(accion)),
        ],
      ),
    );
  }
}
