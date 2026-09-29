/// Lo que el indicador ST456web tiene cargado: recetas, autónomos, guías,
/// trabajos y operarios. El simulador no tiene base de datos, así que es un
/// juego fijo de datos inventados, pensado para ejercitar la app:
///
/// * más trabajos que los 6 que entran en una página de la `11`, para probar
///   `nextPage` y `prevPage`;
/// * trabajos de los tres tipos (`RECE`, `GUIA`, `AUTO`), para los tres
///   caminos de `CTR,select` y los tres tipos de detalle de la `18`;
/// * sólo ASCII, porque la app decodifica en Latin-1 (nada de `ñ`).
///
/// Los índices son texto porque así viajan: la app los muestra y devuelve el
/// del trabajo tal cual en `CTR,detail`.
class St456webCatalog {
  const St456webCatalog({
    required this.recetas,
    required this.autonomos,
    required this.guias,
    required this.trabajos,
    required this.operarios,
    required this.cargaManual,
  });

  final List<St456webReceta> recetas;
  final List<St456webAutonomo> autonomos;
  final List<St456webGuia> guias;
  final List<St456webTrabajo> trabajos;
  final List<St456webOperario> operarios;

  /// Lo que carga `CTR,cargaManual`: la app no manda ingrediente ni cantidad.
  final St456webCargaManual cargaManual;

  St456webReceta? receta(String nombre) =>
      _find(recetas, (r) => r.nombre, nombre);

  St456webGuia? guia(String nombre) => _find(guias, (g) => g.nombre, nombre);

  St456webAutonomo? autonomo(String numero) =>
      _find(autonomos, (a) => a.numero, numero);

  St456webTrabajo? trabajo(String indice) =>
      _find(trabajos, (t) => t.indice, indice);

  /// La receta que carga [trabajo]: la suya si es `RECE`, la de su autónomo
  /// si es `AUTO`, ninguna si es `GUIA`.
  St456webReceta? recetaDe(St456webTrabajo trabajo) {
    switch (trabajo.tipo) {
      case St456webTipoTrabajo.receta:
        return receta(trabajo.receta ?? '');
      case St456webTipoTrabajo.guia:
        return null;
      case St456webTipoTrabajo.autonomo:
        final St456webAutonomo? a = autonomo(trabajo.autonomo ?? '');
        return a == null ? null : receta(a.receta);
    }
  }

  /// La guía que descarga [trabajo]: la suya si es `GUIA`, la de su autónomo
  /// si es `AUTO`, ninguna si es `RECE`.
  St456webGuia? guiaDe(St456webTrabajo trabajo) {
    switch (trabajo.tipo) {
      case St456webTipoTrabajo.receta:
        return null;
      case St456webTipoTrabajo.guia:
        return guia(trabajo.guia ?? '');
      case St456webTipoTrabajo.autonomo:
        final St456webAutonomo? a = autonomo(trabajo.autonomo ?? '');
        return a == null ? null : guia(a.guia);
    }
  }

  /// Los kilos de receta que carga [trabajo], o 0 si no carga.
  int kgDe(St456webTrabajo trabajo) {
    switch (trabajo.tipo) {
      case St456webTipoTrabajo.receta:
        return trabajo.kg;
      case St456webTipoTrabajo.guia:
        return 0;
      case St456webTipoTrabajo.autonomo:
        return autonomo(trabajo.autonomo ?? '')?.kg ?? 0;
    }
  }

  static T? _find<T>(List<T> items, String Function(T) key, String value) {
    for (final T item in items) {
      if (key(item) == value) {
        return item;
      }
    }
    return null;
  }

  static const St456webCatalog demo = St456webCatalog(
    recetas: <St456webReceta>[
      St456webReceta(
        nombre: 'Vacas Lecheras',
        cantidad: 1500,
        minutosMezcla: 2,
        ingredientes: <St456webIngrediente>[
          St456webIngrediente('Maiz', 600),
          St456webIngrediente('Soja', 300),
          St456webIngrediente('Heno', 600),
        ],
      ),
      St456webReceta(
        nombre: 'Terneros',
        cantidad: 800,
        minutosMezcla: 1,
        ingredientes: <St456webIngrediente>[
          St456webIngrediente('Maiz', 400),
          St456webIngrediente('Nucleo', 100),
          St456webIngrediente('Heno', 300),
        ],
      ),
      St456webReceta(
        nombre: 'Engorde',
        cantidad: 2000,
        minutosMezcla: 2,
        ingredientes: <St456webIngrediente>[
          St456webIngrediente('Maiz', 1200),
          St456webIngrediente('Silo', 600),
          St456webIngrediente('Nucleo', 200),
        ],
      ),
      St456webReceta(
        nombre: 'Secas',
        cantidad: 600,
        minutosMezcla: 1,
        ingredientes: <St456webIngrediente>[
          St456webIngrediente('Heno', 500),
          St456webIngrediente('Sales', 100),
        ],
      ),
    ],
    autonomos: <St456webAutonomo>[
      St456webAutonomo(
        numero: '1',
        nombre: 'Autonomo Norte',
        fechaInicial: '01/09/2026',
        fechaFinal: '30/09/2026',
        receta: 'Vacas Lecheras',
        guia: 'Corrales A',
        kg: 1800,
      ),
      St456webAutonomo(
        numero: '2',
        nombre: 'Autonomo Sur',
        fechaInicial: '15/09/2026',
        fechaFinal: '15/10/2026',
        receta: 'Terneros',
        guia: 'Corrales B',
        kg: 800,
      ),
    ],
    guias: <St456webGuia>[
      St456webGuia(
        numero: '1',
        nombre: 'Corrales A',
        lotes: <St456webLote>[
          St456webLote('Corral 1', 1000),
          St456webLote('Corral 2', 800),
        ],
      ),
      St456webGuia(
        numero: '2',
        nombre: 'Corrales B',
        lotes: <St456webLote>[
          St456webLote('Corral 3', 500),
          St456webLote('Corral 4', 300),
        ],
      ),
      St456webGuia(
        numero: '3',
        nombre: 'Lote Norte',
        lotes: <St456webLote>[St456webLote('Lote N', 1000)],
      ),
    ],
    trabajos: <St456webTrabajo>[
      St456webTrabajo(
        indice: '1',
        orden: '1',
        tipo: St456webTipoTrabajo.receta,
        nombre: 'Carga Manana',
        completo: true,
        receta: 'Vacas Lecheras',
        kg: 1500,
      ),
      St456webTrabajo(
        indice: '2',
        orden: '2',
        tipo: St456webTipoTrabajo.guia,
        nombre: 'Descarga Corrales A',
        completo: false,
        guia: 'Corrales A',
      ),
      St456webTrabajo(
        indice: '3',
        orden: '3',
        tipo: St456webTipoTrabajo.autonomo,
        nombre: 'Autonomo Norte',
        completo: false,
        autonomo: '1',
      ),
      St456webTrabajo(
        indice: '4',
        orden: '4',
        tipo: St456webTipoTrabajo.receta,
        nombre: 'Terneros Tarde',
        completo: false,
        receta: 'Terneros',
        kg: 800,
      ),
      St456webTrabajo(
        indice: '5',
        orden: '5',
        tipo: St456webTipoTrabajo.guia,
        nombre: 'Descarga Lote Norte',
        completo: false,
        guia: 'Lote Norte',
      ),
      St456webTrabajo(
        indice: '6',
        orden: '6',
        tipo: St456webTipoTrabajo.autonomo,
        nombre: 'Autonomo Sur',
        completo: false,
        autonomo: '2',
      ),
      St456webTrabajo(
        indice: '7',
        orden: '7',
        tipo: St456webTipoTrabajo.receta,
        nombre: 'Engorde',
        completo: false,
        receta: 'Engorde',
        kg: 2000,
      ),
      St456webTrabajo(
        indice: '8',
        orden: '8',
        tipo: St456webTipoTrabajo.receta,
        nombre: 'Secas',
        completo: false,
        receta: 'Secas',
        kg: 600,
      ),
    ],
    operarios: <St456webOperario>[
      St456webOperario('Dario', '1234'),
      St456webOperario('Estevan', '0000'),
      St456webOperario('Claudio', '4321'),
    ],
    cargaManual: St456webCargaManual(
      nroIngrediente: '1',
      ingrediente: 'Maiz',
      kg: 500,
    ),
  );
}

class St456webReceta {
  const St456webReceta({
    required this.nombre,
    required this.cantidad,
    required this.minutosMezcla,
    required this.ingredientes,
  });

  final String nombre;

  /// Cantidad que precarga la pantalla `8` en el campo editable.
  final int cantidad;
  final int minutosMezcla;

  /// Las cantidades son las de la receta para [cantidad] kg; al iniciar una
  /// carga se escalan con [escalada].
  final List<St456webIngrediente> ingredientes;

  /// Los ingredientes llevados a [kg] kilos. El redondeo se lo come el último
  /// ingrediente, para que la suma dé exacto.
  List<St456webIngrediente> escalada(int kg) {
    final int base = ingredientes.fold<int>(
      0,
      (int suma, St456webIngrediente i) => suma + i.kg,
    );
    if (kg <= 0 || base <= 0 || kg == base) {
      return ingredientes;
    }
    int asignado = 0;
    final List<St456webIngrediente> escalados = <St456webIngrediente>[];
    for (int i = 0; i < ingredientes.length; i++) {
      final St456webIngrediente ing = ingredientes[i];
      final bool ultimo = i == ingredientes.length - 1;
      final int cantidad = ultimo ? kg - asignado : (ing.kg * kg / base).round();
      asignado += cantidad;
      escalados.add(St456webIngrediente(ing.nombre, cantidad));
    }
    return escalados;
  }
}

class St456webIngrediente {
  const St456webIngrediente(this.nombre, this.kg);

  final String nombre;
  final int kg;
}

class St456webAutonomo {
  const St456webAutonomo({
    required this.numero,
    required this.nombre,
    required this.fechaInicial,
    required this.fechaFinal,
    required this.receta,
    required this.guia,
    required this.kg,
  });

  final String numero;
  final String nombre;
  final String fechaInicial;
  final String fechaFinal;

  /// Nombre de la receta que carga.
  final String receta;

  /// Nombre de la guía que descarga después de mezclar.
  final String guia;

  /// Kilos de receta que carga.
  final int kg;
}

class St456webGuia {
  const St456webGuia({
    required this.numero,
    required this.nombre,
    required this.lotes,
  });

  final String numero;
  final String nombre;
  final List<St456webLote> lotes;
}

class St456webLote {
  const St456webLote(this.nombre, this.kg);

  final String nombre;
  final int kg;
}

/// El `tipo` de la pantalla `11`, que decide el ícono en la app y qué pasa al
/// elegir el trabajo.
enum St456webTipoTrabajo {
  receta('RECE'),
  guia('GUIA'),
  autonomo('AUTO');

  const St456webTipoTrabajo(this.code);

  final String code;
}

class St456webTrabajo {
  const St456webTrabajo({
    required this.indice,
    required this.orden,
    required this.tipo,
    required this.nombre,
    required this.completo,
    this.receta,
    this.kg = 0,
    this.guia,
    this.autonomo,
  });

  final String indice;
  final String orden;
  final St456webTipoTrabajo tipo;
  final String nombre;

  /// Si ya figura como realizado al arrancar el simulador.
  final bool completo;

  /// Nombre de la receta y kilos a cargar, en los `RECE`.
  final String? receta;
  final int kg;

  /// Nombre de la guía, en los `GUIA`.
  final String? guia;

  /// Número del autónomo, en los `AUTO`.
  final String? autonomo;
}

class St456webOperario {
  const St456webOperario(this.nombre, this.pin);

  final String nombre;

  /// PIN de 4 dígitos. Viaja en claro: la app lo compara localmente.
  final String pin;
}

class St456webCargaManual {
  const St456webCargaManual({
    required this.nroIngrediente,
    required this.ingrediente,
    required this.kg,
  });

  final String nroIngrediente;
  final String ingrediente;
  final int kg;
}
