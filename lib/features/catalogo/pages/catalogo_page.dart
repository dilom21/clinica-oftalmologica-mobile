import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/session/sesion_clinica.dart';
import '../models/servicio_catalogo.dart';
import '../services/catalogo_service.dart';

class CatalogoPage extends StatefulWidget {
  const CatalogoPage({
    super.key,
    this.service,
    this.clinica,
    this.onSesionInvalida,
  });
  final CatalogoService? service;
  final ClinicaSesion? clinica;
  final VoidCallback? onSesionInvalida;
  @override
  State<CatalogoPage> createState() => _CatalogoPageState();
}

class _CatalogoPageState extends State<CatalogoPage> {
  late final CatalogoService _service = widget.service ?? CatalogoService();
  final _texto = TextEditingController();
  List<ServicioCatalogo> _servicios = [];
  bool _cargando = true, _mas = false;
  String? _error;
  String _busqueda = '';
  int _secuencia = 0;
  Timer? _esperaBusqueda;
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(covariant CatalogoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clinica != widget.clinica) {
      _esperaBusqueda?.cancel();
      _texto.clear();
      _busqueda = '';
      _cargar();
    }
  }

  @override
  void dispose() {
    _secuencia++;
    _esperaBusqueda?.cancel();
    _texto.dispose();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  void _buscarAhora() {
    _esperaBusqueda?.cancel();
    _busqueda = _texto.text.trim();
    _cargar();
  }

  void _alEscribir(String valor) {
    _esperaBusqueda?.cancel();
    // Una respuesta de la búsqueda anterior ya no corresponde al texto actual.
    _secuencia++;
    if (valor.trim().isEmpty) {
      _buscarAhora();
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
      _servicios = [];
      _mas = false;
    });
    _esperaBusqueda = Timer(const Duration(milliseconds: 350), _buscarAhora);
  }

  void _verTodos() {
    _texto.clear();
    _buscarAhora();
  }

  Future<void> _actualizar() {
    _esperaBusqueda?.cancel();
    _busqueda = _texto.text.trim();
    return _cargar();
  }

  Future<void> _cargar({bool agregar = false}) async {
    final solicitud = ++_secuencia;
    final offset = agregar ? _servicios.length : 0;
    setState(() {
      _cargando = true;
      _error = null;
      if (!agregar) _servicios = [];
    });
    try {
      final datos = await _service.listar(busqueda: _busqueda, offset: offset);
      if (!mounted || solicitud != _secuencia) return;
      setState(() {
        _servicios = agregar ? [..._servicios, ...datos] : datos;
        _mas = datos.length == 20;
      });
    } on CatalogoException catch (e) {
      if (!mounted || solicitud != _secuencia) return;
      setState(() => _error = e.mensaje);
      if (e.statusCode == 401) widget.onSesionInvalida?.call();
    } finally {
      if (mounted && solicitud == _secuencia) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Servicios oftalmológicos')),
    body: RefreshIndicator(
      onRefresh: _actualizar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.clinica != null)
            Text(
              widget.clinica!.etiqueta,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          const SizedBox(height: 8),
          const Text('Conoce los servicios disponibles en tu clínica.'),
          const SizedBox(height: 20),
          TextField(
            controller: _texto,
            textInputAction: TextInputAction.search,
            onChanged: _alEscribir,
            onSubmitted: (_) => _buscarAhora(),
            decoration: InputDecoration(
              labelText: 'Buscar por nombre',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Limpiar búsqueda',
                icon: const Icon(Icons.clear),
                onPressed: _verTodos,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _buscarAhora,
            icon: const Icon(Icons.search),
            label: const Text('Buscar'),
          ),
          const SizedBox(height: 20),
          if (_cargando) const Center(child: CircularProgressIndicator()),
          if (_error != null) ...[
            Text(_error!),
            TextButton(
              onPressed: () => _cargar(agregar: _servicios.isNotEmpty),
              child: const Text('Reintentar'),
            ),
          ],
          if (!_cargando && _error == null && _servicios.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _busqueda.isEmpty
                    ? 'No hay servicios disponibles en este momento.'
                    : 'No hay servicios disponibles con esta búsqueda.',
              ),
            ),
          if (!_cargando &&
              _error == null &&
              _servicios.isEmpty &&
              _busqueda.isNotEmpty)
            TextButton.icon(
              onPressed: _verTodos,
              icon: const Icon(Icons.view_list_outlined),
              label: const Text('Ver todos los servicios'),
            ),
          for (final servicio in _servicios)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: const Icon(Icons.visibility_outlined),
                title: Text(servicio.nombre),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${servicio.precioTexto}\n${servicio.duracionTexto}',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ServicioDetallePage(
                      id: servicio.id,
                      service: _service,
                      clinica: widget.clinica,
                      onSesionInvalida: widget.onSesionInvalida,
                    ),
                  ),
                ),
              ),
            ),
          if (_mas && !_cargando && _error == null)
            OutlinedButton(
              onPressed: () => _cargar(agregar: true),
              child: const Text('Cargar más'),
            ),
        ],
      ),
    ),
  );
}

class ServicioDetallePage extends StatefulWidget {
  const ServicioDetallePage({
    super.key,
    required this.id,
    required this.service,
    this.clinica,
    this.onSesionInvalida,
  });
  final int id;
  final CatalogoService service;
  final ClinicaSesion? clinica;
  final VoidCallback? onSesionInvalida;
  @override
  State<ServicioDetallePage> createState() => _ServicioDetallePageState();
}

class _ServicioDetallePageState extends State<ServicioDetallePage> {
  ServicioCatalogo? _servicio;
  String? _error;
  bool _cargando = true;
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
      _servicio = null;
    });
    try {
      final dato = await widget.service.detalle(widget.id);
      if (mounted) setState(() => _servicio = dato);
    } on CatalogoException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
      if (e.statusCode == 401) widget.onSesionInvalida?.call();
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detalle del servicio')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (widget.clinica != null) Text(widget.clinica!.etiqueta),
        if (_cargando) const Center(child: CircularProgressIndicator()),
        if (_error != null) ...[
          Text(_error!),
          TextButton(onPressed: _cargar, child: const Text('Reintentar')),
        ],
        if (_servicio case final servicio?) ...[
          const SizedBox(height: 20),
          Text(
            servicio.nombre,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(
            servicio.descripcion?.trim().isNotEmpty == true
                ? servicio.descripcion!
                : 'Sin descripción disponible.',
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(servicio.precioTexto),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(servicio.duracionTexto),
          ),
        ],
      ],
    ),
  );
}
