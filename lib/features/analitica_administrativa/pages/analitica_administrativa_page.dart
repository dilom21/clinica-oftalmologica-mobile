import 'package:flutter/material.dart';

import '../models/analitica_models.dart';
import '../services/analitica_service.dart';
import '../services/exportacion_analitica_service.dart';
import '../widgets/grafico_analitica.dart';

/// Módulo administrativo. No está enlazado desde [MainNavigationPage], que es
/// exclusiva de pacientes. Debe montarse únicamente desde un shell que ya haya
/// autenticado un administrador con `Generar reportes / LECTURA`.
class AnaliticaAdministrativaPage extends StatelessWidget {
  const AnaliticaAdministrativaPage({
    super.key,
    this.service,
    this.exportacion,
  });
  final AnaliticaService? service;
  final ExportacionAnaliticaService? exportacion;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      backgroundColor: const Color(0xFFF4F8FC),
      appBar: AppBar(
        title: const Text('Reportes y analítica'),
        bottom: const TabBar(
          tabs: <Widget>[
            Tab(text: 'Reportes', icon: Icon(Icons.insights_outlined)),
            Tab(text: 'Pronóstico', icon: Icon(Icons.auto_graph)),
            Tab(text: 'ML', icon: Icon(Icons.model_training_outlined)),
          ],
        ),
      ),
      body: TabBarView(
        children: <Widget>[
          _ReportesTab(
            service: service ?? AnaliticaService(),
            exportacion: exportacion ?? const ExportacionAnaliticaService(),
          ),
          _PronosticoTab(service: service ?? AnaliticaService()),
          _MlTab(service: service ?? AnaliticaService()),
        ],
      ),
    ),
  );
}

class _ReportesTab extends StatefulWidget {
  const _ReportesTab({required this.service, required this.exportacion});
  final AnaliticaService service;
  final ExportacionAnaliticaService exportacion;
  @override
  State<_ReportesTab> createState() => _ReportesTabState();
}

class _ReportesTabState extends State<_ReportesTab> {
  late DateTime _desde = DateTime.now().subtract(const Duration(days: 30));
  late DateTime _hasta = DateTime.now();
  Granularidad _granularidad = Granularidad.dia;
  String? _estado;
  CatalogoProgresivo? _catalogo;
  RespuestaKpis? _kpis;
  RespuestaSerie? _serie;
  RespuestaComparacion? _comparacion;
  String? _indicador;
  String? _error;
  bool _cargando = true;
  bool _exportando = false;
  static const _estados = <String>[
    'PROGRAMADA',
    'CONFIRMADA',
    'EN_ESPERA',
    'ATENDIDA',
    'CANCELADA',
    'NO_ASISTIO',
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  FiltrosProgresivos get _filtros => FiltrosProgresivos(
    fechaDesde: _desde,
    fechaHasta: _hasta,
    granularidad: _granularidad,
    estado: _estado,
  );

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final catalogo = _catalogo ?? await widget.service.catalogo();
      final disponibles = catalogo.indicadores
          .where((i) => i.disponible)
          .toList();
      final indicador =
          _indicador ?? (disponibles.isEmpty ? null : disponibles.first.key);
      final kpis = await widget.service.kpis(_filtros);
      final resultados = indicador == null
          ? null
          : await Future.wait<Object>([
              widget.service.serie(indicador, _filtros),
              widget.service.comparacion(indicador, _filtros),
            ]);
      if (!mounted) return;
      setState(() {
        _catalogo = catalogo;
        _indicador = indicador;
        _kpis = kpis;
        _serie = resultados?[0] as RespuestaSerie?;
        _comparacion = resultados?[1] as RespuestaComparacion?;
        _cargando = false;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _cargando = false;
        });
      }
    }
  }

  Future<void> _fecha(bool desde) async {
    final elegida = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      initialDate: desde ? _desde : _hasta,
    );
    if (elegida == null) return;
    setState(() => desde ? _desde = elegida : _hasta = elegida);
  }

  Future<void> _exportar(String formato) async {
    final indicador = _indicador;
    if (indicador == null) return;
    setState(() => _exportando = true);
    try {
      final archivo = await widget.service.exportar(
        formato,
        indicador,
        _filtros,
      );
      await widget.exportacion.guardar(archivo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reporte ${formato.toUpperCase()} preparado.'),
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _cargar,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _Hero(
          titulo: 'Indicadores progresivos',
          descripcion: 'Datos agregados con cobertura y privacidad visibles.',
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _fecha(true),
                      icon: const Icon(Icons.date_range),
                      label: Text('Desde\n${_fechaTexto(_desde)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _fecha(false),
                      icon: const Icon(Icons.event),
                      label: Text('Hasta\n${_fechaTexto(_hasta)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<Granularidad>(
                initialValue: _granularidad,
                decoration: const InputDecoration(
                  labelText: 'Granularidad',
                  border: OutlineInputBorder(),
                ),
                items: Granularidad.values
                    .map((g) => DropdownMenuItem(value: g, child: Text(g.name)))
                    .toList(),
                onChanged: (v) => setState(() => _granularidad = v!),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: _estado,
                decoration: const InputDecoration(
                  labelText: 'Estado de cita',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  ..._estados.map(
                    (e) => DropdownMenuItem(value: e, child: Text(e)),
                  ),
                ],
                onChanged: (v) => setState(() => _estado = v),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _cargando ? null : _cargar,
                icon: const Icon(Icons.filter_alt),
                label: const Text('Aplicar filtros'),
              ),
            ],
          ),
        ),
        if (_cargando)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _EstadoError(mensaje: _error!, reintentar: _cargar)
        else ...<Widget>[
          const SizedBox(height: 16),
          Text('KPIs', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...?_kpis?.indicadores.map((k) => _KpiCard(kpi: k)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _indicador,
            decoration: const InputDecoration(
              labelText: 'Indicador',
              border: OutlineInputBorder(),
            ),
            items: _catalogo!.indicadores
                .where((i) => i.disponible)
                .map(
                  (i) =>
                      DropdownMenuItem(value: i.key, child: Text(i.etiqueta)),
                )
                .toList(),
            onChanged: (v) {
              setState(() => _indicador = v);
              _cargar();
            },
          ),
          if (_serie != null) ...<Widget>[
            const SizedBox(height: 12),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _serie!.etiqueta,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  GraficoSerie(puntos: _serie!.puntos),
                  ..._serie!.advertencias.map((a) => _Aviso(a)),
                ],
              ),
            ),
          ],
          if (_comparacion != null) ...<Widget>[
            const SizedBox(height: 12),
            _ComparacionCard(value: _comparacion!),
          ],
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Exportar con los filtros actuales',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['csv', 'xlsx', 'pdf']
                      .map(
                        (f) => OutlinedButton(
                          onPressed: _exportando ? null : () => _exportar(f),
                          child: Text(f.toUpperCase()),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          _Aviso(
            'Privacidad: k=${_catalogo!.umbralK}. Un valor nulo nunca se interpreta como cero.',
          ),
        ],
      ],
    ),
  );
}

class _PronosticoTab extends StatefulWidget {
  const _PronosticoTab({required this.service});
  final AnaliticaService service;
  @override
  State<_PronosticoTab> createState() => _PronosticoTabState();
}

class _PronosticoTabState extends State<_PronosticoTab> {
  int _horizonte = 4;
  PronosticoDemanda? _data;
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
    });
    try {
      final d = await widget.service.pronostico(horizonte: _horizonte);
      if (mounted) {
        setState(() {
          _data = d;
          _cargando = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _cargando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      const _Hero(
        titulo: 'Pronóstico semanal',
        descripcion: 'Proyección de citas creadas; no representa ocupación ni asistencia.',
      ),
      const SizedBox(height: 12),
      _Card(
        child: Column(
          children: <Widget>[
            Text('Horizonte: $_horizonte semanas'),
            Slider(
              value: _horizonte.toDouble(),
              min: 4,
              max: 12,
              divisions: 8,
              label: '$_horizonte',
              onChanged: (v) => setState(() => _horizonte = v.round()),
            ),
            FilledButton(
              onPressed: _cargando ? null : _cargar,
              child: const Text('Actualizar pronóstico'),
            ),
          ],
        ),
      ),
      if (_cargando)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_error != null)
        _EstadoError(mensaje: _error!, reintentar: _cargar)
      else if (_data != null) ...<Widget>[
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Badge(_data!.estado),
              const SizedBox(height: 8),
              if (_data!.metodo != null) Text('Método: ${_data!.metodo}'),
              if (_data!.intervalo != null)
                Text('Intervalo: ${_data!.intervalo}'),
              if (_data!.listo)
                GraficoPronostico(puntos: _data!.pronosticos)
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No existe información suficiente para proyectar. Esto no equivale a demanda cero.',
                  ),
                ),
              if (_data!.metricas case final m?)
                Text(
                  'MAE ${m.mae.toStringAsFixed(2)} · RMSE ${m.rmse.toStringAsFixed(2)} · observaciones ${m.observaciones}',
                ),
              const SizedBox(height: 8),
              Text(
                'Cobertura histórica: OK ${_data!.calidad.ok} · ZERO ${_data!.calidad.zero} · SUPPRESSED ${_data!.calidad.suppressed} · PARTIAL ${_data!.calidad.partial} · NOT_COVERED ${_data!.calidad.notCovered}',
              ),
              ..._data!.advertencias.map((a) => _Aviso(a)),
            ],
          ),
        ),
        const _Aviso(
          'El endpoint no publica valores históricos semanales; el gráfico muestra únicamente puntos proyectados.',
        ),
      ],
    ],
  );
}

class _MlTab extends StatefulWidget {
  const _MlTab({required this.service});
  final AnaliticaService service;
  @override
  State<_MlTab> createState() => _MlTabState();
}

class _MlTabState extends State<_MlTab> {
  EstadoModeloInasistencia? _data;
  String? _error;
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final d = await widget.service.estadoInasistencia();
      if (mounted) setState(() => _data = d);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      const _Hero(
        titulo: 'ML de inasistencias',
        descripcion: 'Estado informativo del pipeline; no realiza predicciones individuales.',
      ),
      const SizedBox(height: 12),
      if (_error != null)
        _EstadoError(mensaje: _error!, reintentar: _cargar)
      else if (_data == null)
        const Center(child: CircularProgressIndicator())
      else
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 8,
                children: <Widget>[
                  _Badge(_data!.estado),
                  _Badge(_data!.calidad),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Modelo habilitado: ${_data!.modeloHabilitado ? 'Sí' : 'No'}',
              ),
              Text(
                'Predicción habilitada: ${_data!.prediccionHabilitada ? 'Sí' : 'No'}',
              ),
              _Lista(
                titulo: 'Razones del bloqueo',
                valores: _data!.razonesBloqueo,
              ),
              _Lista(
                titulo: 'Variables permitidas',
                valores: _data!.variablesPermitidas,
              ),
              _Lista(
                titulo: 'Variables excluidas',
                valores: _data!.variablesExcluidas,
              ),
              _Lista(
                titulo: 'Algoritmos disponibles',
                valores: _data!.algoritmos,
              ),
              ..._data!.advertencias.map((a) => _Aviso(a)),
            ],
          ),
        ),
    ],
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.titulo, required this.descripcion});
  final String titulo, descripcion;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF0D47A1),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          titulo,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          descripcion,
          style: const TextStyle(color: Color(0xFFD8ECFA), height: 1.35),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: Color(0xFFDCE6EF)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi});
  final IndicadorKpi kpi;
  @override
  Widget build(BuildContext context) => _Card(
    child: Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                kpi.etiqueta,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (kpi.calificador != null)
                Text(
                  kpi.calificador!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              kpi.valor?.toString() ?? '—',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            _Badge(kpi.estado.valor),
          ],
        ),
      ],
    ),
  );
}

class _ComparacionCard extends StatelessWidget {
  const _ComparacionCard({required this.value});
  final RespuestaComparacion value;
  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Comparación de períodos',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Actual: ${value.actual.valor ?? '—'} (${value.actual.estado.valor})',
        ),
        Text(
          'Anterior: ${value.anterior.valor ?? '—'} (${value.anterior.estado.valor})',
        ),
        Text(
          'Variación: ${value.variacionPorcentual == null ? 'No calculable' : '${value.variacionPorcentual!.toStringAsFixed(1)} %'}',
        ),
        ...value.advertencias.map((a) => _Aviso(a)),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFE3F2FD),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      texto,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Color(0xFF0D47A1),
      ),
    ),
  );
}

class _Aviso extends StatelessWidget {
  const _Aviso(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.info_outline, size: 17, color: Color(0xFFF57C00)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(fontSize: 12.5, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class _Lista extends StatelessWidget {
  const _Lista({required this.titulo, required this.valores});
  final String titulo;
  final List<String> valores;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
        if (valores.isEmpty)
          const Text('Sin elementos reportados')
        else
          ...valores.map((v) => Text('• $v')),
      ],
    ),
  );
}

class _EstadoError extends StatelessWidget {
  const _EstadoError({required this.mensaje, required this.reintentar});
  final String mensaje;
  final VoidCallback reintentar;
  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      children: <Widget>[
        const Icon(Icons.error_outline, color: Colors.red),
        const SizedBox(height: 8),
        Text(mensaje, textAlign: TextAlign.center),
        TextButton(onPressed: reintentar, child: const Text('Reintentar')),
      ],
    ),
  );
}

String _fechaTexto(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
