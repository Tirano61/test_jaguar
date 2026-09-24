/// Pantallas que el simulador puede representar en el modo Remoto ST407.
///
/// Los códigos van de 100 a 110 porque ese es el rango que los protocolos
/// remotos reservan para el indicador ST407: `protocolo-simulador-st456web.md`
/// y `protocolo-simulador-st567.md` listan `100`-`110` como "pantallas
/// reservadas que el simulador no debe usar", justamente porque pertenecen al
/// ST407. El rango 60-68 que usaba antes este enum pisaba la pantalla `60` del
/// ST567 ("elegir receta con preset").
///
/// Faltan dos códigos a propósito: `105` (cargando autónomo) no tiene página
/// en la app y `107` (más mezcla) es solo un popup.
enum St407Screen {
  main(100, '100 - Pantalla principal'),
  loadingRecipe(101, '101 - Cargando por recetas'),
  loadingManual(102, '102 - Cargando manual'),
  unloadingGuide(103, '103 - Descargando por guia'),
  unloadingManual(104, '104 - Descargando manual'),
  mixing(106, '106 - Mezclando'),
  chooseRecipe(108, '108 - Elegir receta'),
  chooseAutonomous(109, '109 - Elegir autonomo'),
  chooseGuide(110, '110 - Elegir guia');

  const St407Screen(this.code, this.label);

  final int code;
  final String label;
}
