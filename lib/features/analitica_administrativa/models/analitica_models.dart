enum EstadoDato { ok, zero, suppressed, partial, notCovered }

extension EstadoDatoJson on EstadoDato {
  String get valor => switch (this) {
    EstadoDato.ok => 'OK',
    EstadoDato.zero => 'ZERO',
    EstadoDato.suppressed => 'SUPPRESSED',
    EstadoDato.partial => 'PARTIAL',
    EstadoDato.notCovered => 'NOT_COVERED',
  };

  static EstadoDato parse(Object? value) => switch (value) {
    'OK' => EstadoDato.ok,
    'ZERO' => EstadoDato.zero,
    'SUPPRESSED' => EstadoDato.suppressed,
    'PARTIAL' => EstadoDato.partial,
    'NOT_COVERED' => EstadoDato.notCovered,
    _ => throw FormatException('Estado de dato desconocido: $value'),
  };
}

enum Granularidad { dia, semana, mes }

extension GranularidadJson on Granularidad {
  String get valor => name;
}

class FiltrosProgresivos {
  const FiltrosProgresivos({
    required this.fechaDesde,
    required this.fechaHasta,
    this.granularidad = Granularidad.dia,
    this.estado,
  });

  final DateTime fechaDesde;
  final DateTime fechaHasta;
  final Granularidad granularidad;
  final String? estado;

  void validar() {
    final desde = DateTime(fechaDesde.year, fechaDesde.month, fechaDesde.day);
    final hasta = DateTime(fechaHasta.year, fechaHasta.month, fechaHasta.day);
    if (desde.isAfter(hasta)) {
      throw const FormatException(
        'La fecha inicial no puede ser posterior a la final.',
      );
    }
    if (hasta.difference(desde).inDays > 366) {
      throw const FormatException('El rango máximo es de 366 días.');
    }
  }

  Map<String, String> toQuery() {
    validar();
    return <String, String>{
      'fecha_desde': _fecha(fechaDesde),
      'fecha_hasta': _fecha(fechaHasta),
      'granularidad': granularidad.valor,
      if (estado != null && estado!.isNotEmpty) 'estado': estado!,
    };
  }

  Map<String, dynamic> toJson({required String indicador}) => <String, dynamic>{
    ...toQuery(),
    'indicador': indicador,
  };

  static String _fecha(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class IndicadorCatalogo {
  const IndicadorCatalogo({
    required this.key,
    required this.etiqueta,
    required this.disponible,
    required this.limitaciones,
    this.codigo,
    this.calificador,
    this.rangoMaximoDias,
  });

  final String key;
  final String etiqueta;
  final bool disponible;
  final List<String> limitaciones;
  final String? codigo;
  final String? calificador;
  final int? rangoMaximoDias;

  factory IndicadorCatalogo.fromJson(Map<String, dynamic> json) =>
      IndicadorCatalogo(
        key: json['key'] as String,
        etiqueta: json['etiqueta'] as String,
        disponible: json['disponible'] as bool,
        limitaciones: _strings(json['limitaciones']),
        codigo: json['codigo'] as String?,
        calificador: json['calificador'] as String?,
        rangoMaximoDias: json['rango_maximo_dias'] as int?,
      );
}

class CatalogoProgresivo {
  const CatalogoProgresivo({
    required this.version,
    required this.umbralK,
    required this.estados,
    required this.indicadores,
  });
  final String version;
  final int umbralK;
  final List<EstadoDato> estados;
  final List<IndicadorCatalogo> indicadores;

  factory CatalogoProgresivo.fromJson(Map<String, dynamic> json) {
    final politica = json['politica_privacidad'] as Map<String, dynamic>;
    return CatalogoProgresivo(
      version: json['version'] as String,
      umbralK: politica['umbral_k'] as int,
      estados: (politica['estados'] as List).map(EstadoDatoJson.parse).toList(),
      indicadores: (json['indicadores'] as List)
          .map((e) => IndicadorCatalogo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ValorAgregado {
  const ValorAgregado({required this.valor, required this.estado});
  final num? valor;
  final EstadoDato estado;
  factory ValorAgregado.fromJson(Map<String, dynamic> json) => ValorAgregado(
    valor: json['valor'] as num?,
    estado: EstadoDatoJson.parse(json['estado_dato']),
  );
}

class IndicadorKpi extends ValorAgregado {
  const IndicadorKpi({
    required super.valor,
    required super.estado,
    required this.indicador,
    required this.etiqueta,
    required this.advertencias,
    this.calificador,
  });
  final String indicador;
  final String etiqueta;
  final String? calificador;
  final List<String> advertencias;
  factory IndicadorKpi.fromJson(Map<String, dynamic> json) => IndicadorKpi(
    valor: json['valor'] as num?,
    estado: EstadoDatoJson.parse(json['estado_dato']),
    indicador: json['indicador'] as String,
    etiqueta: json['etiqueta'] as String,
    calificador: json['calificador'] as String?,
    advertencias: _strings(json['advertencias']),
  );
}

class RespuestaKpis {
  const RespuestaKpis({
    required this.indicadores,
    required this.distribucionEstados,
    required this.advertencias,
    required this.zonaHoraria,
  });
  final List<IndicadorKpi> indicadores;
  final List<IndicadorKpi> distribucionEstados;
  final List<String> advertencias;
  final String zonaHoraria;
  factory RespuestaKpis.fromJson(Map<String, dynamic> json) => RespuestaKpis(
    indicadores: (json['indicadores'] as List)
        .map((e) => IndicadorKpi.fromJson(e as Map<String, dynamic>))
        .toList(),
    distribucionEstados: (json['distribucion_estados'] as List)
        .map((e) => IndicadorKpi.fromJson(e as Map<String, dynamic>))
        .toList(),
    advertencias: _strings(json['advertencias']),
    zonaHoraria: json['zona_horaria'] as String,
  );
}

class PuntoSerie extends ValorAgregado {
  const PuntoSerie({
    required super.valor,
    required super.estado,
    required this.inicio,
    required this.fin,
  });
  final DateTime inicio;
  final DateTime fin;
  factory PuntoSerie.fromJson(Map<String, dynamic> json) => PuntoSerie(
    valor: json['valor'] as num?,
    estado: EstadoDatoJson.parse(json['estado_dato']),
    inicio: DateTime.parse(json['periodo_inicio'] as String),
    fin: DateTime.parse(json['periodo_fin'] as String),
  );
}

class RespuestaSerie {
  const RespuestaSerie({
    required this.indicador,
    required this.etiqueta,
    required this.puntos,
    required this.advertencias,
  });
  final String indicador;
  final String etiqueta;
  final List<PuntoSerie> puntos;
  final List<String> advertencias;
  factory RespuestaSerie.fromJson(Map<String, dynamic> json) => RespuestaSerie(
    indicador: json['indicador'] as String,
    etiqueta: json['etiqueta'] as String,
    puntos: (json['puntos'] as List)
        .map((e) => PuntoSerie.fromJson(e as Map<String, dynamic>))
        .toList(),
    advertencias: _strings(json['advertencias']),
  );
}

class RespuestaComparacion {
  const RespuestaComparacion({
    required this.actual,
    required this.anterior,
    required this.advertencias,
    this.variacionAbsoluta,
    this.variacionPorcentual,
  });
  final ValorAgregado actual;
  final ValorAgregado anterior;
  final num? variacionAbsoluta;
  final num? variacionPorcentual;
  final List<String> advertencias;
  factory RespuestaComparacion.fromJson(Map<String, dynamic> json) =>
      RespuestaComparacion(
        actual: ValorAgregado.fromJson(json['actual'] as Map<String, dynamic>),
        anterior: ValorAgregado.fromJson(
          json['anterior'] as Map<String, dynamic>,
        ),
        variacionAbsoluta: json['variacion_absoluta'] as num?,
        variacionPorcentual: json['variacion_porcentual'] as num?,
        advertencias: _strings(json['advertencias']),
      );
}

class MetricasPronostico {
  const MetricasPronostico({
    required this.mae,
    required this.rmse,
    required this.wape,
    required this.sesgo,
    required this.observaciones,
  });
  final double mae;
  final double rmse;
  final double? wape;
  final double sesgo;
  final int observaciones;
  factory MetricasPronostico.fromJson(Map<String, dynamic> json) =>
      MetricasPronostico(
        mae: (json['mae'] as num).toDouble(),
        rmse: (json['rmse'] as num).toDouble(),
        wape: (json['wape'] as num?)?.toDouble(),
        sesgo: (json['sesgo'] as num).toDouble(),
        observaciones: json['observaciones'] as int,
      );
}

class PronosticoSemana {
  const PronosticoSemana({
    required this.inicio,
    required this.fin,
    required this.valor,
    required this.limiteInferior,
    required this.limiteSuperior,
  });
  final DateTime inicio;
  final DateTime fin;
  final double valor;
  final double limiteInferior;
  final double limiteSuperior;
  factory PronosticoSemana.fromJson(Map<String, dynamic> json) =>
      PronosticoSemana(
        inicio: DateTime.parse(json['inicio_semana'] as String),
        fin: DateTime.parse(json['fin_semana'] as String),
        valor: (json['valor_pronosticado'] as num).toDouble(),
        limiteInferior: (json['limite_inferior'] as num).toDouble(),
        limiteSuperior: (json['limite_superior'] as num).toDouble(),
      );
}

class CalidadHistorica {
  const CalidadHistorica({
    required this.ok,
    required this.zero,
    required this.suppressed,
    required this.partial,
    required this.notCovered,
  });
  final int ok;
  final int zero;
  final int suppressed;
  final int partial;
  final int notCovered;
  factory CalidadHistorica.fromJson(Map<String, dynamic> json) =>
      CalidadHistorica(
        ok: json['semanas_ok'] as int,
        zero: json['semanas_zero'] as int,
        suppressed: json['semanas_suppressed'] as int,
        partial: json['semanas_partial'] as int,
        notCovered: json['semanas_not_covered'] as int,
      );
}

class PronosticoDemanda {
  const PronosticoDemanda({
    required this.estado,
    required this.horizonte,
    required this.calidad,
    required this.pronosticos,
    required this.advertencias,
    this.metodo,
    this.intervalo,
    this.metricas,
    this.rangoInicio,
    this.rangoFin,
  });
  final String estado;
  final int horizonte;
  final String? metodo;
  final String? intervalo;
  final MetricasPronostico? metricas;
  final CalidadHistorica calidad;
  final DateTime? rangoInicio;
  final DateTime? rangoFin;
  final List<PronosticoSemana> pronosticos;
  final List<String> advertencias;
  bool get listo => estado == 'READY';
  factory PronosticoDemanda.fromJson(Map<String, dynamic> json) =>
      PronosticoDemanda(
        estado: json['estado'] as String,
        horizonte: json['horizonte_semanas'] as int,
        metodo: json['metodo'] as String?,
        intervalo: json['intervalo'] as String?,
        metricas: json['metricas'] == null
            ? null
            : MetricasPronostico.fromJson(
                json['metricas'] as Map<String, dynamic>,
              ),
        calidad: CalidadHistorica.fromJson(
          json['calidad_historica'] as Map<String, dynamic>,
        ),
        rangoInicio: _fechaOpcional(json['rango_historico_inicio']),
        rangoFin: _fechaOpcional(json['rango_historico_fin']),
        pronosticos: (json['pronosticos'] as List)
            .map((e) => PronosticoSemana.fromJson(e as Map<String, dynamic>))
            .toList(),
        advertencias: _strings(json['advertencias']),
      );
}

class EstadoModeloInasistencia {
  const EstadoModeloInasistencia({
    required this.estado,
    required this.calidad,
    required this.modeloHabilitado,
    required this.prediccionHabilitada,
    required this.algoritmos,
    required this.variablesPermitidas,
    required this.variablesExcluidas,
    required this.razonesBloqueo,
    required this.advertencias,
  });
  final String estado;
  final String calidad;
  final bool modeloHabilitado;
  final bool prediccionHabilitada;
  final List<String> algoritmos;
  final List<String> variablesPermitidas;
  final List<String> variablesExcluidas;
  final List<String> razonesBloqueo;
  final List<String> advertencias;
  factory EstadoModeloInasistencia.fromJson(Map<String, dynamic> json) =>
      EstadoModeloInasistencia(
        estado: json['estado'] as String,
        calidad: json['calidad'] as String,
        modeloHabilitado: json['modelo_habilitado'] as bool,
        prediccionHabilitada: json['prediccion_habilitada'] as bool,
        algoritmos: _strings(json['algoritmos_disponibles']),
        variablesPermitidas: _strings(json['variables_permitidas']),
        variablesExcluidas: _strings(json['variables_excluidas']),
        razonesBloqueo: _strings(json['razones_bloqueo']),
        advertencias: _strings(json['advertencias']),
      );
}

List<String> _strings(Object? value) =>
    (value as List? ?? const <Object>[]).map((e) => e.toString()).toList();
DateTime? _fechaOpcional(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
