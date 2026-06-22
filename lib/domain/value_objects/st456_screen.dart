enum St456Screen {
  main(60, '60 - Pantalla principal'),
  loadingRecipe(61, '61 - Cargando por recetas'),
  loadingManual(62, '62 - Cargando manual'),
  unloadingGuide(63, '63 - Descargando por guia'),
  unloadingManual(64, '64 - Descargando manual'),
  mixing(65, '65 - Mezclando'),
  chooseRecipe(66, '66 - Elegir receta'),
  chooseAutonomous(67, '67 - Elegir autonomo'),
  chooseGuide(68, '68 - Elegir guia');

  const St456Screen(this.code, this.label);

  final int code;
  final String label;
}
