enum SimulationPhase {
  loadedWaiting,
  unloading,
  emptyWaiting,
  loading,
}

extension SimulationPhaseX on SimulationPhase {
  String get label {
    switch (this) {
      case SimulationPhase.loadedWaiting:
        return 'CAMION CARGADO ESPERANDO';
      case SimulationPhase.unloading:
        return 'DESCARGA';
      case SimulationPhase.emptyWaiting:
        return 'CAMION VACIO ESPERANDO';
      case SimulationPhase.loading:
        return 'NUEVA CARGA';
    }
  }
}
