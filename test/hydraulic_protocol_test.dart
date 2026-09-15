import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_actuator_position.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_discharge_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_movement_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_protocol.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_pto.dart';

/// El módulo Hidráulico se prueba solo: no necesita orquestador, ni BLE, ni
/// motor de simulación. Las pruebas de integración con el resto del simulador
/// siguen en `simulator_orchestrator_hydraulic_test.dart`.
void main() {
  HydraulicProtocol conPeso(int peso) {
    final HydraulicProtocol p = HydraulicProtocol();
    p.setPeso(peso);
    return p;
  }

  HydraulicDischargeCommand inicio(String raw) =>
      HydraulicDischargeCommand.tryParse(raw)!;

  test('una descarga baja el peso por tick hasta el objetivo', () {
    final HydraulicProtocol p = conPeso(1000);
    p.applyInicio(inicio('AT+INICIO=500,300,100,1,2')); // velocidad 2: 50 kg

    expect(p.advance(humidity: 10.0).peso, 950);
    expect(p.advance(humidity: 10.0).peso, 900);

    for (int i = 0; i < 10 && p.state.dischargeActive; i++) {
      p.advance(humidity: 10.0);
    }
    expect(p.state.dischargeActive, isFalse);
    expect(p.measurement(humidity: 10.0).peso, 500);
  });

  test('el evento de guardado se entrega una sola vez', () {
    final HydraulicProtocol p = conPeso(100);
    p.applyInicio(inicio('AT+INICIO=100,50,10,2,2')); // modo 2: dos descargas

    expect(p.takeCompletedSaveEvent(), isNull, reason: 'todavía no completó');
    p.advance(humidity: 10.0); // 100 -> 50 -> objetivo 0 en el siguiente
    p.advance(humidity: 10.0);

    expect(p.takeCompletedSaveEvent(), HydraulicSaveEvent.guardarDos);
    expect(p.takeCompletedSaveEvent(), isNull, reason: 'ya se consumió');
  });

  test('AT+FINALIZAR descarta la corrida sin dejar evento de guardado', () {
    final HydraulicProtocol p = conPeso(1000);
    p.applyInicio(inicio('AT+INICIO=500,300,100,2,2'));
    p.advance(humidity: 10.0);

    p.applyFinalizar();

    expect(p.state.dischargeActive, isFalse);
    expect(p.takeCompletedSaveEvent(), isNull);
    // El modo 2 de la corrida descartada no se le pega a la próxima.
    p.applyInicio(inicio('AT+INICIO=950,300,100,1,2'));
    while (p.state.dischargeActive) {
      p.advance(humidity: 10.0);
    }
    expect(p.takeCompletedSaveEvent(), HydraulicSaveEvent.guardar);
  });

  test('la configuración sobrevive al reset de la corrida', () {
    final HydraulicProtocol p = conPeso(1000);
    p.setTomaFuerza(HydraulicPtoState.on);
    p.setTomaFuerzaRpm(800);
    p.setErrorEcu('E42');
    p.applyInicio(inicio('AT+INICIO=500,300,100,1,2'));

    p.resetRunState();

    expect(p.state.dischargeActive, isFalse);
    expect(p.state.tuboPosicion, HydraulicActuatorPosition.closed);
    // tomaFuerza, rpm y errorEcu son configuración del tester, no de la corrida.
    expect(p.state.tomaFuerza, HydraulicPtoState.on);
    expect(p.state.tomaFuerzaRpm, 800);
    expect(p.state.errorEcu, 'E42');
  });

  test('los setters devuelven null cuando no cambian nada', () {
    final HydraulicProtocol p = conPeso(1000);

    expect(p.setPeso(1000), isNull, reason: 'mismo peso');
    expect(p.setErrorEcu(''), isNull, reason: 'mismo errorEcu');
    expect(p.setTomaFuerzaRpm(HydraulicPtoRpm.defaultValue), isNull);

    p.applyInicio(inicio('AT+INICIO=500,300,100,1,2'));
    expect(p.setPeso(200), isNull, reason: 'no se edita durante una descarga');
  });

  test('AT+MOVIMIENTO mueve un paso y satura en los topes', () {
    final HydraulicProtocol p = conPeso(1000);
    final HydraulicMovementCommand abrirTubo =
        HydraulicMovementCommand.tryParse('AT+MOVIMIENTO=1')!;

    for (int i = 0; i < 10; i++) {
      p.applyMovimiento(abrirTubo);
    }

    expect(p.state.tuboPosicion, HydraulicActuatorPosition.open);
  });

  test('el JSON lleva rpm sólo con la toma de fuerza encendida', () {
    final HydraulicProtocol p = conPeso(1000);
    p.setTomaFuerzaRpm(800);

    expect(p.encodePayload(p.measurement(humidity: 10.0)), contains('"rpm":0'));

    p.setTomaFuerza(HydraulicPtoState.on);
    expect(
      p.encodePayload(p.measurement(humidity: 10.0)),
      contains('"rpm":800'),
    );
  });
}
