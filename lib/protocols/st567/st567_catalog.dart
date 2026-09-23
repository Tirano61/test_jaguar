/// Lo que el indicador ST567 tiene cargado: recetas, ingredientes, trabajos y
/// operarios. El simulador no tiene base de datos, así que es un juego fijo de
/// datos inventados, pensado para ejercitar la app:
///
/// * más ítems que los que entran en una página, para probar `nextPage` y
///   `prevPage`;
/// * un trabajo cuyos lotes piden más de lo que se carga, para llegar al
///   diálogo `40` ("Debe preparar más carga");
/// * sólo ASCII, porque la app decodifica en Latin-1 (nada de `ñ`).
///
/// Los índices son texto porque así viajan: la app los muestra y los devuelve
/// tal cual en `CTR,select` y `CTR,detail`.
class St567Catalog {
  const St567Catalog({
    required this.recetas,
    required this.ingredientes,
    required this.trabajos,
    required this.operarios,
  });

  final List<St567Receta> recetas;
  final List<St567Ingrediente> ingredientes;
  final List<St567Trabajo> trabajos;
  final List<St567Operario> operarios;

  St567Receta? receta(String indice) => _find(recetas, (r) => r.indice, indice);

  St567Ingrediente? ingrediente(String indice) =>
      _find(ingredientes, (i) => i.indice, indice);

  St567Trabajo? trabajo(String indice) =>
      _find(trabajos, (t) => t.indice, indice);

  static T? _find<T>(List<T> items, String Function(T) key, String indice) {
    for (final T item in items) {
      if (key(item) == indice) {
        return item;
      }
    }
    return null;
  }

  static const St567Catalog demo = St567Catalog(
    recetas: <St567Receta>[
      St567Receta(
        indice: '1',
        nombre: 'Vacas Lecheras',
        preset: 1500,
        mezclaSeg: 30,
        tipo: 0,
        ingredientes: <St567IngredienteReceta>[
          St567IngredienteReceta('Maiz', 600, tipoAviso: 1, aviso: 10, mezclaSeg: 30),
          St567IngredienteReceta('Soja', 300, tipoAviso: 0, aviso: 20, mezclaSeg: 30),
          St567IngredienteReceta('Heno', 600, tipoAviso: 1, aviso: 15, mezclaSeg: 60),
        ],
      ),
      St567Receta(
        indice: '2',
        nombre: 'Terneros',
        preset: 800,
        mezclaSeg: 20,
        tipo: 1,
        ingredientes: <St567IngredienteReceta>[
          St567IngredienteReceta('Maiz', 400, tipoAviso: 1, aviso: 10, mezclaSeg: 20),
          St567IngredienteReceta('Nucleo', 100, tipoAviso: 0, aviso: 10, mezclaSeg: 20),
          St567IngredienteReceta('Heno', 300, tipoAviso: 1, aviso: 10, mezclaSeg: 30),
        ],
      ),
      St567Receta(
        indice: '3',
        nombre: 'Engorde',
        preset: 2000,
        mezclaSeg: 45,
        tipo: 0,
        ingredientes: <St567IngredienteReceta>[
          St567IngredienteReceta('Maiz', 1200, tipoAviso: 1, aviso: 10, mezclaSeg: 30),
          St567IngredienteReceta('Silo', 600, tipoAviso: 1, aviso: 10, mezclaSeg: 45),
          St567IngredienteReceta('Nucleo', 200, tipoAviso: 0, aviso: 20, mezclaSeg: 30),
        ],
      ),
      St567Receta(
        indice: '4',
        nombre: 'Vaquillonas',
        preset: 1000,
        mezclaSeg: 30,
        tipo: 0,
        ingredientes: <St567IngredienteReceta>[
          St567IngredienteReceta('Silo', 700, tipoAviso: 1, aviso: 10, mezclaSeg: 30),
          St567IngredienteReceta('Expeller', 300, tipoAviso: 1, aviso: 10, mezclaSeg: 30),
        ],
      ),
      St567Receta(
        indice: '5',
        nombre: 'Secas',
        preset: 600,
        mezclaSeg: 20,
        tipo: 0,
        ingredientes: <St567IngredienteReceta>[
          St567IngredienteReceta('Heno', 500, tipoAviso: 1, aviso: 10, mezclaSeg: 20),
          St567IngredienteReceta('Sales', 100, tipoAviso: 0, aviso: 5, mezclaSeg: 20),
        ],
      ),
      St567Receta(
        indice: '6',
        nombre: 'Toros',
        preset: 1200,
        mezclaSeg: 30,
        tipo: 1,
        ingredientes: <St567IngredienteReceta>[
          St567IngredienteReceta('Maiz', 600, tipoAviso: 1, aviso: 10, mezclaSeg: 30),
          St567IngredienteReceta('Heno', 600, tipoAviso: 1, aviso: 10, mezclaSeg: 30),
        ],
      ),
      St567Receta(
        indice: '7',
        nombre: 'Recria',
        preset: 900,
        mezclaSeg: 25,
        tipo: 0,
        ingredientes: <St567IngredienteReceta>[
          St567IngredienteReceta('Silo', 500, tipoAviso: 1, aviso: 10, mezclaSeg: 25),
          St567IngredienteReceta('Maiz', 300, tipoAviso: 1, aviso: 10, mezclaSeg: 25),
          St567IngredienteReceta('Nucleo', 100, tipoAviso: 0, aviso: 10, mezclaSeg: 25),
        ],
      ),
    ],
    ingredientes: <St567Ingrediente>[
      St567Ingrediente('1', 'Maiz'),
      St567Ingrediente('2', 'Soja'),
      St567Ingrediente('3', 'Heno'),
      St567Ingrediente('4', 'Nucleo'),
      St567Ingrediente('5', 'Silo'),
      St567Ingrediente('6', 'Expeller'),
      St567Ingrediente('7', 'Sales'),
    ],
    trabajos: <St567Trabajo>[
      St567Trabajo(
        indice: '1',
        nombre: 'Trabajo Manana',
        receta: '1',
        kg: 1500,
        bachada: '2',
        porcentaje: '50',
        viajes: '4',
        completo: true,
        lotes: <St567Lote>[St567Lote('Corral 1', 800), St567Lote('Corral 2', 700)],
      ),
      St567Trabajo(
        indice: '2',
        nombre: 'Trabajo Tarde',
        receta: '2',
        kg: 800,
        bachada: '1',
        porcentaje: '100',
        viajes: '2',
        completo: false,
        // Piden 1000 kg y se cargan 800: después del segundo lote el mixer
        // queda vacío y todavía falta el tercero.
        lotes: <St567Lote>[
          St567Lote('Corral 3', 500),
          St567Lote('Corral 4', 300),
          St567Lote('Corral 5', 200),
        ],
      ),
      St567Trabajo(
        indice: '3',
        nombre: 'Trabajo Noche',
        receta: '3',
        kg: 2000,
        bachada: '1',
        porcentaje: '100',
        viajes: '1',
        completo: false,
        lotes: <St567Lote>[St567Lote('Corral 6', 1200), St567Lote('Corral 7', 800)],
      ),
      St567Trabajo(
        indice: '4',
        nombre: 'Vaquillonas Norte',
        receta: '4',
        kg: 1000,
        bachada: '1',
        porcentaje: '100',
        viajes: '1',
        completo: false,
        lotes: <St567Lote>[St567Lote('Lote N', 1000)],
      ),
      St567Trabajo(
        indice: '5',
        nombre: 'Secas Sur',
        receta: '5',
        kg: 600,
        bachada: '1',
        porcentaje: '100',
        viajes: '1',
        completo: false,
        lotes: <St567Lote>[St567Lote('Lote S', 600)],
      ),
      St567Trabajo(
        indice: '6',
        nombre: 'Recria Oeste',
        receta: '7',
        kg: 900,
        bachada: '1',
        porcentaje: '100',
        viajes: '1',
        completo: false,
        lotes: <St567Lote>[St567Lote('Lote O1', 450), St567Lote('Lote O2', 450)],
      ),
    ],
    operarios: <St567Operario>[
      St567Operario('Dario', '1234'),
      St567Operario('Estevan', '0000'),
      St567Operario('Claudio', '4321'),
    ],
  );
}

class St567Receta {
  const St567Receta({
    required this.indice,
    required this.nombre,
    required this.preset,
    required this.mezclaSeg,
    required this.tipo,
    required this.ingredientes,
  });

  final String indice;
  final String nombre;

  /// Cantidad que precarga la pantalla `60` en el diálogo de inicio.
  final int preset;
  final int mezclaSeg;

  /// `0` = KG, `1` = Cabezas. Sólo se muestra en el detalle.
  final int tipo;

  /// Las cantidades son las de la receta para [preset] kg; al iniciar una
  /// carga se escalan a la cantidad que pida la app.
  final List<St567IngredienteReceta> ingredientes;
}

class St567IngredienteReceta {
  const St567IngredienteReceta(
    this.nombre,
    this.cantidad, {
    required this.tipoAviso,
    required this.aviso,
    required this.mezclaSeg,
  });

  final String nombre;
  final int cantidad;

  /// `0` = el aviso está en kg, `1` = en porcentaje de [cantidad].
  final int tipoAviso;
  final int aviso;
  final int mezclaSeg;
}

class St567Ingrediente {
  const St567Ingrediente(this.indice, this.nombre);

  final String indice;
  final String nombre;
}

class St567Trabajo {
  const St567Trabajo({
    required this.indice,
    required this.nombre,
    required this.receta,
    required this.kg,
    required this.bachada,
    required this.porcentaje,
    required this.viajes,
    required this.completo,
    required this.lotes,
  });

  final String indice;
  final String nombre;

  /// Índice de la receta que se carga.
  final String receta;

  /// Kilos a cargar de la receta.
  final int kg;

  // Estos tres sólo se muestran en el detalle; el simulador no los usa.
  final String bachada;
  final String porcentaje;
  final String viajes;

  /// Si ya figura como realizado al arrancar el simulador.
  final bool completo;
  final List<St567Lote> lotes;
}

class St567Lote {
  const St567Lote(this.nombre, this.kg);

  final String nombre;
  final int kg;
}

class St567Operario {
  const St567Operario(this.nombre, this.pin);

  final String nombre;

  /// PIN de 4 dígitos. Viaja en claro: la app lo compara localmente.
  final String pin;
}
