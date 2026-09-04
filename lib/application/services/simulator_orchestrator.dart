import 'dart:async';

import 'package:test_jaguar/application/dto/hydraulic_payload_dto.dart';
import 'package:test_jaguar/application/dto/scale_payload_dto.dart';
import 'package:test_jaguar/application/dto/st456_payload_dto.dart';
import 'package:test_jaguar/application/dto/simulator_status_dto.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/core/extensions/stream_subscription_extensions.dart';
import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/repositories/ble_peripheral_repository.dart';
import 'package:test_jaguar/domain/repositories/scale_simulation_repository.dart';
import 'package:test_jaguar/domain/value_objects/hydraulic_discharge_command.dart';
import 'package:test_jaguar/domain/value_objects/hydraulic_movement_command.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/domain/value_objects/st456_screen.dart';

class SimulatorOrchestrator {
  SimulatorOrchestrator({
    required BlePeripheralRepository bleRepository,
    required ScaleSimulationRepository simulationRepository,
  })  : _bleRepository = bleRepository,
        _simulationRepository = simulationRepository {
    _bindSources();
  }

  final BlePeripheralRepository _bleRepository;
  final ScaleSimulationRepository _simulationRepository;

  final StreamController<SimulatorStatusDto> _statusController =
      StreamController<SimulatorStatusDto>.broadcast();

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  static const int _weightHoldTicksAfterSensorChange = 5;
  static const String _resetHoldCommand = 'AT+RSTHOLD';
  static const String _toggleTareCommand = 'AT+TARA';
  static const String _zeroWeightCommand = 'AT+CERO';

  SendProtocol _sendProtocol = SendProtocol.jaguarBle;
  St456Screen _st456Screen = St456Screen.main;
  double _selectedHumidity = 10.0;
  ScaleMeasurement _manualMeasurement = ScaleMeasurement.baseline;
  // Estado para simulación de "kg a cargar" y parcial en pantallas ST456
  double? _st456InitialKgToLoad;
  // Peso actual mostrado en la pantalla de carga (disminuye lentamente)
  double _st456CurrentDisplayedPeso = 0.0;
  bool _st456LoadingActive = false;
  // decremento por tick aplicado al peso actual mostrado
  final double _st456DecrementPerTick = 1.0;
  // Estado de cuenta regresiva para pantalla 65 (mezclando): inicia en 4:30
  bool _st456MixingCountdownActive = false;
  int _st456MixingCurrentSeconds = 4 * 60 + 30;
  int _lastSensorInduc = SimulatorStatusDto.initial.measurement.sensorInduc;
  int _weightHoldTicksRemaining = 0;
  int? _heldWeight;
  SimulatorStatusDto _current = SimulatorStatusDto.initial;

  // --- Estado modo Hidráulico BLE ---
  // Peso/sensor propios de este modo: no dependen del motor de simulación
  // automático (no hay ciclo de fases acá). sensorInduc queda siempre en 0
  // (carga) — la transición carga/descarga la maneja la app conectada por
  // AT+INICIO/AT+GUARDAR, no el sensor. peso solo cambia si el tester lo
  // edita a mano o por una descarga activa iniciada con AT+INICIO.
  ScaleMeasurement _hydraulicMeasurement = ScaleMeasurement.baseline;
  int _tomaFuerza = 0;
  String _errorEcu = '';
  bool _tuboAbierto = false;
  bool _guillotinaAbierta = false;
  HydraulicDischargeCommand? _lastHydraulicInicio;
  HydraulicMovementCommand? _lastHydraulicMovimiento;
  bool _hydraulicDischargeActive = false;
  bool _hydraulicJustCompleted = false;
  double _hydraulicCurrentDisplayedPeso = 0.0;
  double _hydraulicInitialPeso = 0.0;
  double _hydraulicTargetPeso = 0.0;
  double _hydraulicDecrementPerTick = 0.0;
  int _lastProcessedCommandSequence = -1;

  double get selectedHumidity => _selectedHumidity;

  Stream<SimulatorStatusDto> watchStatus() => _statusController.stream;

  Future<void> start() async {
    await _bleRepository.startAdvertising();
    await _simulationRepository.start();
    _pushLog('Simulacion iniciada');
  }

  Future<void> stop() async {
    await _simulationRepository.stop();
    await _bleRepository.stopAdvertising();
    _pushLog('Simulacion detenida');
  }

  Future<void> setSendProtocol(SendProtocol protocol) async {
    if (_sendProtocol == protocol) {
      return;
    }
    _sendProtocol = protocol;
    await _bleRepository.updateBleUuids(
      protocol == SendProtocol.st456Remote
          ? BleConstants.st456
          : BleConstants.jaguar,
    );
    _weightHoldTicksRemaining = 0;
    _heldWeight = null;
    _lastSensorInduc = _current.measurement.sensorInduc;

    // Limpiar estado ST456 si ya no estamos en ese protocolo
    if (_sendProtocol != SendProtocol.st456Remote) {
      _st456LoadingActive = false;
      _st456InitialKgToLoad = null;
      _st456CurrentDisplayedPeso = 0.0;
      _st456MixingCountdownActive = false;
      _st456MixingCurrentSeconds = 4 * 60 + 30;
    }

    // Limpiar estado de ejecución hidráulico si ya no estamos en ese
    // protocolo (tomaFuerza/errorEcu se conservan, son configuración, no
    // estado de una corrida en curso).
    if (_sendProtocol != SendProtocol.hidraulicoBle) {
      _hydraulicDischargeActive = false;
      _hydraulicCurrentDisplayedPeso = 0.0;
      _hydraulicInitialPeso = 0.0;
      _hydraulicTargetPeso = 0.0;
      _hydraulicDecrementPerTick = 0.0;
      _tuboAbierto = false;
      _guillotinaAbierta = false;
    }

    _emit(_withHydraulicSnapshot(_current.copyWith(sendProtocol: _sendProtocol)));
    _pushLog('Protocolo seleccionado: ${protocol.label}');
    await _sendCurrentPayloadNow();
  }

  Future<void> setHydraulicPeso(int value) async {
    if (_hydraulicDischargeActive) {
      return; // no se edita a mano mientras hay una descarga en curso
    }
    final int next = value.clamp(0, 22000);
    if (_hydraulicMeasurement.peso == next) {
      return;
    }
    _hydraulicMeasurement = _hydraulicMeasurement.copyWith(peso: next);
    _pushLog('Peso hidráulico configurado: $next kg');
    await _sendCurrentPayloadNow();
  }

  Future<void> setTomaFuerza(int value) async {
    final int next = value.clamp(0, 3);
    if (_tomaFuerza == next) {
      return;
    }
    _tomaFuerza = next;
    _pushLog('Toma de fuerza configurada: $_tomaFuerza');
    await _sendCurrentPayloadNow();
  }

  Future<void> setErrorEcu(String value) async {
    if (_errorEcu == value) {
      return;
    }
    _errorEcu = value;
    _pushLog('errorEcu configurado: "$_errorEcu"');
    await _sendCurrentPayloadNow();
  }

  /// Envía el evento `AT+GUARDAR` crudo por notify BLE. Se dispara solo al
  /// completar una descarga simulada, y también puede forzarse a mano desde
  /// la UI en cualquier momento.
  Future<void> sendGuardarEvent() async {
    try {
      await _bleRepository.notifyUtf8Json('AT+GUARDAR\r\n');
    } catch (error) {
      _pushLog('Error enviando AT+GUARDAR: $error');
      return;
    }
    _pushLog('AT+GUARDAR enviado');
  }

  Future<void> setSt456Screen(St456Screen screen) async {
    if (_st456Screen == screen) {
      return;
    }

    _st456Screen = screen;
    _emit(_current.copyWith(st456Screen: _st456Screen));
    _pushLog('Pantalla ST456 seleccionada: ${screen.label}');

    if (_sendProtocol == SendProtocol.st456Remote) {
      // Inicializar estado de carga cuando se seleccionan pantallas de carga
      if (screen == St456Screen.loadingRecipe || screen == St456Screen.loadingManual) {
        _st456InitialKgToLoad = _current.measurement.peso.toDouble();
        // peso mostrado parte del peso actual y luego irá bajando
        _st456CurrentDisplayedPeso = _st456InitialKgToLoad ?? 0.0;
        _st456LoadingActive = true;
        _st456MixingCountdownActive = false;
        _st456MixingCurrentSeconds = 4 * 60 + 30;
      } else if (screen == St456Screen.mixing) {
        _st456LoadingActive = false;
        _st456InitialKgToLoad = null;
        _st456CurrentDisplayedPeso = 0.0;
        _st456MixingCountdownActive = true;
        _st456MixingCurrentSeconds = 4 * 60 + 30;
      } else {
        _st456LoadingActive = false;
        _st456InitialKgToLoad = null;
        _st456CurrentDisplayedPeso = 0.0;
        _st456MixingCountdownActive = false;
        _st456MixingCurrentSeconds = 4 * 60 + 30;
      }
      await _sendCurrentPayloadNow();
    }
  }

  Future<void> setManualMeasurement(ScaleMeasurement measurement) async {
    _manualMeasurement = _normalizeManualMeasurement(measurement);
    _emit(_current.copyWith(manualMeasurement: _manualMeasurement));

    if (_sendProtocol == SendProtocol.manual) {
      await _sendCurrentPayloadNow();
    }
  }

  Future<void> setHumidity(double value) async {
    _selectedHumidity = _normalizeHumidity(value);
    final updatedMeasurement =
        _current.measurement.copyWith(humedad: _selectedHumidity);
    _emit(_current.copyWith(measurement: updatedMeasurement));
    await _sendCurrentPayloadNow();
    _pushLog('Humedad configurada: ${_selectedHumidity.toStringAsFixed(1)}');
  }

  Future<void> dispose() async {
    await _subscriptions.cancelAll();
    await _simulationRepository.dispose();
    await _bleRepository.dispose();
    await _statusController.close();
  }

  void _bindSources() {
    _subscriptions.add(
      _bleRepository.watchStatus().listen((status) async {
        final List<String> logs = _logsForBleStatusChange(
          previous: _current.bleStatus,
          next: status,
        );
        _emit(
          _current.copyWith(
            bleStatus: status,
            logs: logs.isEmpty
                ? _current.logs
                : <String>[...logs, ..._current.logs].take(100).toList(),
          ),
        );

        // status.commandSequence sólo cambia con un write real; sin este
        // guard, cualquier emisión de watchStatus() no relacionada
        // (adapter on/off, conexión de central, etc.) reprocesaría el mismo
        // último comando recibido, lo cual es inaceptable para AT+INICIO
        // (reiniciaría la descarga simulada) y AT+GUARDAR (se reenviaría).
        if (status.commandSequence != _lastProcessedCommandSequence) {
          _lastProcessedCommandSequence = status.commandSequence;
          await _applyIncomingCommandIfNeeded(status.lastReceivedCommand);
        }
      }),
    );

    _subscriptions.add(
      _simulationRepository.watchRunning().listen((running) {
        _emit(_current.copyWith(running: running));
      }),
    );

    _subscriptions.add(
      _simulationRepository.watchPhase().listen((phase) {
        _emit(_current.copyWith(phase: phase));
      }),
    );

    _subscriptions.add(
      _simulationRepository.watchMeasurements().listen((measurement) async {
        final ScaleMeasurement outgoingMeasurement =
            _measurementForCurrentProtocol(measurement);
        await _notifyAndEmitMeasurement(
          outgoingMeasurement,
          weightHoldSecondsRemaining:
              _sendProtocol == SendProtocol.manual
                  ? 0
                  : _weightHoldTicksRemaining,
        );

        if (_hydraulicJustCompleted) {
          _hydraulicJustCompleted = false;
          _pushLog(
            'Descarga hidráulica completada (peso objetivo alcanzado): '
            'enviando AT+GUARDAR',
          );
          await sendGuardarEvent();
        }
      }),
    );
  }

  Future<void> _sendCurrentPayloadNow() async {
    final ScaleMeasurement measurement = _sendProtocol == SendProtocol.manual
        ? _manualMeasurement
        : _current.measurement.copyWith(humedad: _selectedHumidity);
    await _notifyAndEmitMeasurement(
      measurement,
      weightHoldSecondsRemaining:
          _sendProtocol == SendProtocol.manual ? 0 : _weightHoldTicksRemaining,
    );
  }

  Future<void> _notifyAndEmitMeasurement(
    ScaleMeasurement measurement, {
    required int weightHoldSecondsRemaining,
  }) async {
    final String payload = _payloadForCurrentProtocol(measurement);
    try {
      await _bleRepository.notifyUtf8Json(payload);
    } catch (error) {
      _pushLog('Error notify BLE: $error');
    }

    _emit(
      _withHydraulicSnapshot(
        _current.copyWith(
          measurement: measurement,
          sendProtocol: _sendProtocol,
          st456Screen: _st456Screen,
          manualMeasurement: _manualMeasurement,
          weightHoldSecondsRemaining: weightHoldSecondsRemaining,
          lastJson: payload,
        ),
      ),
    );
  }

  SimulatorStatusDto _withHydraulicSnapshot(SimulatorStatusDto value) {
    return value.copyWith(
      tomaFuerza: _tomaFuerza,
      errorEcu: _errorEcu,
      tuboAbierto: _tuboAbierto,
      guillotinaAbierta: _guillotinaAbierta,
      hydraulicDischargeActive: _hydraulicDischargeActive,
      hydraulicInitialPeso: _hydraulicInitialPeso,
      hydraulicTargetPeso: _hydraulicTargetPeso,
      lastHydraulicInicio: _lastHydraulicInicio,
      lastHydraulicMovimiento: _lastHydraulicMovimiento,
    );
  }

  String _payloadForCurrentProtocol(ScaleMeasurement measurement) {
    if (_sendProtocol == SendProtocol.hidraulicoBle) {
      return HydraulicPayloadDto(
        measurement: measurement,
        tomaFuerza: _tomaFuerza,
        errorEcu: _errorEcu,
      ).toJsonUtf8String();
    }

    if (_sendProtocol == SendProtocol.st456Remote) {
      // Para pantallas de carga (loadingRecipe, loadingManual) necesitamos
      // mantener un 'kg a cargar' que parte del valor inicial de peso actual
      // y va disminuyendo muy de a poco; el campo 'parcial' debe reflejar
      // lo que ya se fue descargando (initial - current).
      if (_st456Screen == St456Screen.loadingRecipe ||
          _st456Screen == St456Screen.loadingManual) {
        // Asegurar inicialización del valor estático "kg a cargar"
        if (!_st456LoadingActive || _st456InitialKgToLoad == null) {
          _st456InitialKgToLoad = measurement.peso.toDouble();
          _st456CurrentDisplayedPeso = _st456InitialKgToLoad ?? 0.0;
          _st456LoadingActive = true;
        }

        // 'kg a cargar' debe mantener el valor inicial (estático)
        final double initial = _st456InitialKgToLoad ?? measurement.peso.toDouble();
        // 'peso actual' se toma del measurement que llega (debe bajar)
        final double pesoActual = measurement.peso.toDouble();
        // 'parcial' es lo que ya se descargó: initial - pesoActual (no negativo)
        final int parcial = (initial - pesoActual).clamp(0.0, double.infinity).round();
        final int kgACargar = initial.round();

        // Construir cadena según la pantalla
        if (_st456Screen == St456Screen.loadingRecipe) {
          // formato: pantalla,peso_actual,parcial,kg_a_cargar,ingrediente
          return '${_st456Screen.code},${pesoActual.round()},$parcial,$kgACargar,Maiz\r\n';
        }

        if (_st456Screen == St456Screen.loadingManual) {
          // ingrediente/identificador distinto en la pantalla manual
          return '${_st456Screen.code},${pesoActual.round()},$parcial,$kgACargar,1\r\n';
        }
      }

      // Pantalla 65 - mezclando: formato pantalla,minutos,segundos
      // Debe iniciar en 65,4,30 y decrementar como reloj.
      if (_st456Screen == St456Screen.mixing) {
        if (!_st456MixingCountdownActive) {
          _st456MixingCountdownActive = true;
          _st456MixingCurrentSeconds = 4 * 60 + 30;
        }

        final int minutes = _st456MixingCurrentSeconds ~/ 60;
        final int seconds = _st456MixingCurrentSeconds % 60;
        final String seconds2 = seconds.toString().padLeft(2, '0');
        final String payload = '${_st456Screen.code},$minutes,$seconds2\r\n';

        if (_st456MixingCurrentSeconds > 0) {
          _st456MixingCurrentSeconds -= 1;
        }

        return payload;
      }

      return St456PayloadDto(
        screen: _st456Screen,
        measurement: measurement,
        now: DateTime.now(),
      ).toProtocolString();
    }

    return ScalePayloadDto(measurement: measurement).toJsonUtf8String();
  }

  ScaleMeasurement _measurementForCurrentProtocol(ScaleMeasurement measurement) {
    if (_sendProtocol == SendProtocol.manual) {
      return _manualMeasurement;
    }

    // Hidráulico BLE no usa el motor de simulación automático (measurement,
    // el tick de fases carga/descarga): el peso queda fijo salvo que el
    // tester lo edite a mano o haya una descarga activa por AT+INICIO, y
    // sensorInduc nunca cambia (la app conectada maneja la transición
    // carga/descarga por comando, no por sensor).
    if (_sendProtocol == SendProtocol.hidraulicoBle) {
      if (_hydraulicDischargeActive) {
        final double next =
            _hydraulicCurrentDisplayedPeso - _hydraulicDecrementPerTick;
        if (next <= _hydraulicTargetPeso) {
          _hydraulicCurrentDisplayedPeso = _hydraulicTargetPeso;
          _hydraulicDischargeActive = false;
          _hydraulicJustCompleted = true;
          _hydraulicMeasurement = _hydraulicMeasurement.copyWith(
            peso: _hydraulicCurrentDisplayedPeso.round(),
          );
        } else {
          _hydraulicCurrentDisplayedPeso = next;
        }
        return _hydraulicMeasurement.copyWith(
          peso: _hydraulicCurrentDisplayedPeso.round(),
          humedad: _selectedHumidity,
        );
      }
      return _hydraulicMeasurement.copyWith(humedad: _selectedHumidity);
    }

    ScaleMeasurement base = measurement.copyWith(humedad: _selectedHumidity);

    // Si estamos en protocolo ST456 remoto y en una pantalla de carga, debemos
    // mostrar un peso actual que disminuye lentamente mientras 'kg a cargar'
    // permanece estático (inicial). Para ello usamos _st456CurrentDisplayedPeso.
    if (_sendProtocol == SendProtocol.st456Remote &&
        (_st456Screen == St456Screen.loadingRecipe ||
            _st456Screen == St456Screen.loadingManual)) {
      // Inicializar si es la primera vez
      if (!_st456LoadingActive || _st456InitialKgToLoad == null) {
        _st456InitialKgToLoad = base.peso.toDouble();
        _st456CurrentDisplayedPeso = _st456InitialKgToLoad ?? base.peso.toDouble();
        _st456LoadingActive = true;
      }

      // Decrementar el peso mostrado muy de a poco
      double next = _st456CurrentDisplayedPeso - _st456DecrementPerTick;
      if (next < 0.0) next = 0.0;
      _st456CurrentDisplayedPeso = next;

      // Devolver measurement con el peso modificado para UI y payload
      return base.copyWith(peso: _st456CurrentDisplayedPeso.round());
    }

    return _withScaleStateFromWeightChange(_withWeightHoldAfterSensorChange(base));
  }

  double _normalizeHumidity(double value) {
    final double clamped = value.clamp(0.0, 22.0);
    return double.parse(clamped.toStringAsFixed(1));
  }

  ScaleMeasurement _normalizeManualMeasurement(ScaleMeasurement measurement) {
    final double normalizedHumidity =
        double.parse(measurement.humedad.clamp(0.0, 22.0).toStringAsFixed(1));
    final double normalizedVbat =
        double.parse(measurement.vbat.clamp(0.0, 5.0).toStringAsFixed(1));

    return measurement.copyWith(
      tara: measurement.tara.clamp(0, 22000),
      hold: measurement.hold.clamp(0, 1),
      vbat: normalizedVbat,
      peso: measurement.peso.clamp(0, 22000),
      estBalanza: measurement.estBalanza.clamp(0, 5),
      humedad: normalizedHumidity,
      sensorInduc: measurement.sensorInduc.clamp(0, 1),
    );
  }

  ScaleMeasurement _withWeightHoldAfterSensorChange(
    ScaleMeasurement measurement,
  ) {
    final int previousSensorInduc = _lastSensorInduc;
    if (measurement.sensorInduc != previousSensorInduc) {
      _lastSensorInduc = measurement.sensorInduc;
      _weightHoldTicksRemaining = _weightHoldTicksAfterSensorChange;
      _heldWeight = _current.measurement.peso;
      _pushLog(
        'Cambio sensorInduc $previousSensorInduc -> ${measurement.sensorInduc}: peso congelado 5s',
      );
    }

    if (_weightHoldTicksRemaining > 0 && _heldWeight != null) {
      _weightHoldTicksRemaining -= 1;
      return measurement.copyWith(peso: _heldWeight);
    }

    return measurement;
  }

  ScaleMeasurement _withScaleStateFromWeightChange(
    ScaleMeasurement measurement,
  ) {
    final bool weightChanged = measurement.peso != _current.measurement.peso;
    return measurement.copyWith(estBalanza: weightChanged ? 0 : 1);
  }

  Future<void> _applyIncomingCommandIfNeeded(String? command) async {
    if (command == null || command.isEmpty) {
      return;
    }

    final String normalizedCommand = _normalizeIncomingCommand(command);
    if (normalizedCommand.isEmpty) {
      return;
    }

    if (_isResetHoldCommand(normalizedCommand)) {
      final ScaleMeasurement nextManual = _normalizeManualMeasurement(
        _manualMeasurement.copyWith(
          hold: 0,
          estBalanza: 1,
        ),
      );

      if (nextManual.hold == _manualMeasurement.hold &&
          nextManual.estBalanza == _manualMeasurement.estBalanza) {
        return;
      }

      _manualMeasurement = nextManual;
      _emit(_current.copyWith(manualMeasurement: _manualMeasurement));
      _pushLog('Comando aplicado: AT+RSTHOLD -> hold=0');
      await _sendCurrentPayloadNow();
      return;
    }

    if (_isToggleTareCommand(normalizedCommand)) {
      if (_sendProtocol != SendProtocol.manual) {
        return;
      }

      final bool activateTare = _manualMeasurement.tara == 0;
      final ScaleMeasurement toggledMeasurement = activateTare
          ? _manualMeasurement.copyWith(
              tara: _manualMeasurement.peso,
              peso: 0,
            )
          : _manualMeasurement.copyWith(
              tara: 0,
              peso: (_manualMeasurement.peso + _manualMeasurement.tara)
                  .clamp(0, 22000)
                  .toInt(),
            );
      final ScaleMeasurement nextManual =
          _normalizeManualMeasurement(toggledMeasurement);

      if (nextManual.tara == _manualMeasurement.tara &&
          nextManual.peso == _manualMeasurement.peso) {
        return;
      }

      _manualMeasurement = nextManual;
      _emit(_current.copyWith(manualMeasurement: _manualMeasurement));
      _pushLog(
        activateTare
            ? 'Comando aplicado: AT+TARA -> tara activada'
            : 'Comando aplicado: AT+TARA -> tara desactivada',
      );
      await _sendCurrentPayloadNow();
      return;
    }

    if (_isZeroWeightCommand(normalizedCommand)) {
      if (_sendProtocol == SendProtocol.manual) {
        if (_manualMeasurement.tara > 0 || _manualMeasurement.peso == 0) {
          return;
        }

        _manualMeasurement = _normalizeManualMeasurement(
          _manualMeasurement.copyWith(peso: 0),
        );
        _emit(_current.copyWith(manualMeasurement: _manualMeasurement));
        _pushLog('Comando aplicado: AT+CERO -> peso=0 (manual)');
        await _sendCurrentPayloadNow();
        return;
      }

      final ScaleMeasurement currentMeasurement = _current.measurement;
      if (currentMeasurement.tara > 0 || currentMeasurement.peso == 0) {
        return;
      }

      final ScaleMeasurement zeroedMeasurement =
          currentMeasurement.copyWith(peso: 0);
      _pushLog('Comando aplicado: AT+CERO -> peso=0 (jaguar)');
      await _notifyAndEmitMeasurement(
        zeroedMeasurement,
        weightHoldSecondsRemaining: _weightHoldTicksRemaining,
      );
      return;
    }

    final HydraulicDischargeCommand? inicio =
        HydraulicDischargeCommand.tryParse(normalizedCommand);
    if (inicio != null) {
      if (_sendProtocol == SendProtocol.hidraulicoBle) {
        await _applyHydraulicInicio(inicio);
      } else {
        _pushLog(
          'AT+INICIO recibido pero se ignora: seleccioná "Hidráulico BLE" '
          'para procesarlo (${inicio.summary}).',
        );
      }
      return;
    }

    final HydraulicMovementCommand? movimiento =
        HydraulicMovementCommand.tryParse(normalizedCommand);
    if (movimiento != null) {
      if (_sendProtocol == SendProtocol.hidraulicoBle) {
        await _applyHydraulicMovimiento(movimiento);
      } else {
        _pushLog(
          'AT+MOVIMIENTO recibido pero se ignora: seleccioná "Hidráulico BLE" '
          'para procesarlo (${movimiento.label}).',
        );
      }
      return;
    }
  }

  Future<void> _applyHydraulicInicio(HydraulicDischargeCommand command) async {
    _lastHydraulicInicio = command;

    final int currentPeso = _current.measurement.peso;
    final bool validRange = command.hasValidRange;
    final bool validAgainstCurrent = command.kgDescarga < currentPeso;

    if (!validRange || !validAgainstCurrent) {
      _pushLog(
        'AT+INICIO recibido con parámetros inválidos (${command.summary}): '
        'se requiere kgDescarga > kgTubo y kgDescarga < peso actual '
        '($currentPeso kg). No se inicia la descarga simulada.',
      );
      await _sendCurrentPayloadNow();
      return;
    }

    _hydraulicCurrentDisplayedPeso = currentPeso.toDouble();
    _hydraulicInitialPeso = currentPeso.toDouble();
    _hydraulicTargetPeso = (currentPeso - command.kgDescarga).toDouble();
    _hydraulicDecrementPerTick = _hydraulicRateForVelocidad(command.velocidad);
    _hydraulicDischargeActive = true;

    _pushLog('AT+INICIO recibido: ${command.summary}');
    await _sendCurrentPayloadNow();
  }

  Future<void> _applyHydraulicMovimiento(
    HydraulicMovementCommand command,
  ) async {
    _lastHydraulicMovimiento = command;

    final bool? opens = command.opens;
    if (command.affectsTube && opens != null) {
      _tuboAbierto = opens;
    } else if (command.affectsGuillotine && opens != null) {
      _guillotinaAbierta = opens;
    }

    _pushLog('AT+MOVIMIENTO recibido: ${command.label} (tipo=${command.tipo})');
    await _sendCurrentPayloadNow();
  }

  double _hydraulicRateForVelocidad(int velocidad) {
    switch (velocidad) {
      case 1:
        return 20.0; // lenta
      case 2:
        return 50.0; // normal
      case 3:
        return 120.0; // rápida
      case 4:
        return 70.0; // variable (valor intermedio fijo, sin jitter)
      default:
        return 50.0;
    }
  }

  String _normalizeIncomingCommand(String command) {
    return command
        .toUpperCase()
        .replaceAll(RegExp(r'\\[RNS]'), '')
        .replaceAll(RegExp(r'\\X[0-9A-F]{2}'), '')
        .replaceAll(RegExp(r'[\r\n\t\s]'), '')
        .replaceAll(r'\', '')
        .trim();
  }

  bool _isResetHoldCommand(String normalizedCommand) =>
      normalizedCommand == _resetHoldCommand;

  bool _isToggleTareCommand(String normalizedCommand) =>
      normalizedCommand == _toggleTareCommand || normalizedCommand == 'TARA';

  bool _isZeroWeightCommand(String normalizedCommand) =>
      normalizedCommand == _zeroWeightCommand || normalizedCommand == 'CERO';

  List<String> _logsForBleStatusChange({
    required BlePeripheralStatus previous,
    required BlePeripheralStatus next,
  }) {
    final List<String> logs = <String>[];

    if (previous.adapterEnabled != next.adapterEnabled) {
      logs.add(next.adapterEnabled ? 'BLE habilitado' : 'BLE deshabilitado');
    }

    if (previous.advertising != next.advertising) {
      logs.add(next.advertising
          ? 'Advertising BLE iniciado'
          : 'Advertising BLE detenido');
    }

    if (previous.connected != next.connected) {
      logs.add(next.connected
          ? 'Central BLE conectada'
          : 'Central BLE desconectada');
    }

    if (previous.connectedDeviceId != next.connectedDeviceId &&
        next.connectedDeviceId != null) {
      logs.add('Central activa: ${next.connectedDeviceId}');
    }

    if (previous.lastReceivedCommand != next.lastReceivedCommand &&
        next.lastReceivedCommand != null &&
        next.lastReceivedCommand!.isNotEmpty) {
      logs.add('Comando recibido: ${next.lastReceivedCommand}');
    }

    return logs;
  }

  void _pushLog(String line) {
    final List<String> updatedLogs = <String>[line, ..._current.logs];
    _emit(_current.copyWith(logs: updatedLogs.take(100).toList()));
  }

  void _emit(SimulatorStatusDto value) {
    _current = value;
    if (!_statusController.isClosed) {
      _statusController.add(value);
    }
  }
}
