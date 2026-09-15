import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_actuators.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_discharge_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_movement_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_protocol.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_pto.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_state.dart';

/// El módulo Hidráulico se prueba solo: no necesita orquestador, ni BLE, ni
/// motor de simulación. Los dos relojes se hacen avanzar a mano —`advance()`
/// es el tick del motor (mueve el peso) y `advanceActuators()` el reloj de
/// actuadores (mueve tubo y guillotina)—, así que no hay que esperar segundos
/// reales.
void main() {
  const Duration unSegundo = Duration(seconds: 1);

  HydraulicProtocol conPeso(int peso, {int semilla = 7}) {
    final HydraulicProtocol p = HydraulicProtocol(random: Random(semilla));
    p.setPeso(peso);
    return p;
  }

  HydraulicDischargeCommand inicio(String raw) =>
      HydraulicDischargeCommand.tryParse(raw)!;

  /// Corre el reloj de actuadores [segundos] veces y devuelve todo lo que
  /// quedó pendiente en el camino.
  List<HydraulicActuatorTick> correrActuadores(
    HydraulicProtocol p,
    int segundos,
  ) {
    return <HydraulicActuatorTick>[
      for (int i = 0; i < segundos; i++) p.advanceActuators(unSegundo),
    ];
  }

  group('ciclo de descarga', () {
    test('AT+INICIO abre el tubo antes de empezar a descargar', () {
      final HydraulicProtocol p = conPeso(1000);

      p.applyInicio(inicio('AT+INICIO=500,300,100,1,2'));

      expect(p.state.phase, HydraulicRunPhase.abriendoTubo);
      expect(p.state.tubo, TubeState.abriendo);

      // Aunque corra el motor, el peso no se mueve hasta que el tubo abra.
      p.advance(humidity: 10.0);
      expect(p.measurement(humidity: 10.0).peso, 1000);
    });

    test('el tubo tarda exactamente 6 s en abrir', () {
      final HydraulicProtocol p = conPeso(1000);
      p.applyInicio(inicio('AT+INICIO=500,300,100,1,2'));

      correrActuadores(p, 5);
      expect(p.state.tubo, TubeState.abriendo, reason: 'a los 5 s sigue abriendo');

      p.advanceActuators(unSegundo);
      expect(p.state.tubo, TubeState.abierto);
      expect(p.state.phase, HydraulicRunPhase.descargando);
    });

    test('la guillotina se abre a 25% al arrancar la descarga', () {
      final HydraulicProtocol p = conPeso(1000);
      p.applyInicio(inicio('AT+INICIO=500,300,100,1,2'));

      expect(p.state.gillo, 0);
      // Recorrido completo 15 s, asi que 25% tarda 4 pasos de 1 s.
      correrActuadores(p, 4);
      expect(p.state.gillo, HydraulicGuillotine.dischargeOpenPercent);
    });

    test('con el tubo abierto el peso baja por tick del motor', () {
      final HydraulicProtocol p = conPeso(1000);
      p.applyInicio(inicio('AT+INICIO=500,300,100,1,2')); // velocidad 2: 50 kg
      correrActuadores(p, 6);

      expect(p.advance(humidity: 10.0).peso, 950);
      expect(p.advance(humidity: 10.0).peso, 900);
    });

    test('al llegar al objetivo guarda y cierra tubo y guillotina', () {
      final HydraulicProtocol p = conPeso(100);
      p.applyInicio(inicio('AT+INICIO=100,50,10,2,2')); // modo 2: dos descargas
      correrActuadores(p, 6);

      // 100 kg a 50 kg por tick: dos ticks del motor.
      p.advance(humidity: 10.0);
      p.advance(humidity: 10.0);
      expect(p.measurement(humidity: 10.0).peso, 0);

      // El evento sale en el primer paso del reloj de actuadores posterior.
      final HydraulicActuatorTick tick = p.advanceActuators(unSegundo);
      expect(tick.saveEvent, HydraulicSaveEvent.guardarDos);
      expect(p.state.phase, HydraulicRunPhase.cerrandoTubo);
      expect(p.state.tubo, TubeState.cerrando);

      // Se entrega una sola vez.
      expect(p.advanceActuators(unSegundo).saveEvent, isNull);
    });

    test('el tubo tarda 6 s en cerrar y ahi termina la corrida', () {
      final HydraulicProtocol p = conPeso(100);
      p.applyInicio(inicio('AT+INICIO=100,50,10,1,2'));
      correrActuadores(p, 6);
      p.advance(humidity: 10.0);
      p.advance(humidity: 10.0);
      p.advanceActuators(unSegundo); // dispara el guardado y arranca el cierre

      correrActuadores(p, 5);
      expect(p.state.tubo, TubeState.cerrando);

      p.advanceActuators(unSegundo);
      expect(p.state.tubo, TubeState.cerrado);
      expect(p.state.phase, HydraulicRunPhase.idle);
      expect(p.state.gillo, 0, reason: 'la guillotina tambien cierra');
    });

    test('la guillotina regula entre 25 y 80 cada 5 s durante la descarga', () {
      final HydraulicProtocol p = conPeso(20000);
      p.applyInicio(inicio('AT+INICIO=19000,300,100,1,1'));
      correrActuadores(p, 6);

      final List<int> valores = <int>[];
      for (int i = 0; i < 20; i++) {
        p.advanceActuators(unSegundo);
        valores.add(p.state.gillo);
      }

      // Cambia cada 5 pasos, no en cada uno.
      final Set<int> distintos = valores.toSet();
      expect(distintos.length, greaterThan(1));
      expect(distintos.length, lessThanOrEqualTo(5));
      for (final int v in valores) {
        expect(
          v,
          inInclusiveRange(
            HydraulicGuillotine.dischargeMinPercent,
            HydraulicGuillotine.dischargeMaxPercent,
          ),
        );
      }
    });
  });

  group('AT+FINALIZAR', () {
    test('descarta la corrida, cierra la guillotina y deja el tubo', () {
      final HydraulicProtocol p = conPeso(1000);
      p.applyInicio(inicio('AT+INICIO=500,300,100,2,2'));
      correrActuadores(p, 6);
      p.advance(humidity: 10.0);

      p.applyFinalizar();

      expect(p.state.phase, HydraulicRunPhase.idle);
      expect(p.state.tubo, TubeState.abierto, reason: 'el tubo queda como esta');
      correrActuadores(p, 15);
      expect(p.state.gillo, 0, reason: 'la guillotina si cierra');
    });

    test('el modo 2 descartado no se le pega a la proxima corrida', () {
      final HydraulicProtocol p = conPeso(1000);
      p.applyInicio(inicio('AT+INICIO=500,300,100,2,2'));
      correrActuadores(p, 6);
      p.advance(humidity: 10.0);
      p.applyFinalizar();

      p.applyInicio(inicio('AT+INICIO=950,300,100,1,2'));
      correrActuadores(p, 6);
      while (p.state.phase == HydraulicRunPhase.descargando) {
        p.advance(humidity: 10.0);
        if (p.advanceActuators(unSegundo).saveEvent != null) {
          break;
        }
      }
      // La corrida anterior era modo 2; esta es modo 1 y cierra con AT+GUARDAR.
      expect(p.state.phase, HydraulicRunPhase.cerrandoTubo);
    });
  });

  group('AT+MOVIMIENTO manual', () {
    final HydraulicMovementCommand abrirTubo =
        HydraulicMovementCommand.tryParse('AT+MOVIMIENTO=1')!;
    final HydraulicMovementCommand cerrarTubo =
        HydraulicMovementCommand.tryParse('AT+MOVIMIENTO=2')!;
    final HydraulicMovementCommand abrirGuillotina =
        HydraulicMovementCommand.tryParse('AT+MOVIMIENTO=3')!;

    test('el tubo tarda 15 s en abrir del todo', () {
      final HydraulicProtocol p = conPeso(1000);

      p.applyMovimiento(abrirTubo);
      expect(p.state.tubo, TubeState.abriendo);

      correrActuadores(p, 14);
      expect(p.state.tubo, TubeState.abriendo);
      p.advanceActuators(unSegundo);
      expect(p.state.tubo, TubeState.abierto);
    });

    test('cerrar a mitad de la apertura vuelve desde donde quedo', () {
      final HydraulicProtocol p = conPeso(1000);
      p.applyMovimiento(abrirTubo);
      correrActuadores(p, 6); // 6/15 del recorrido

      p.applyMovimiento(cerrarTubo);
      expect(p.state.tubo, TubeState.cerrando);

      // Tiene que volver esos mismos 6 s, no los 15 enteros.
      correrActuadores(p, 5);
      expect(p.state.tubo, TubeState.cerrando);
      p.advanceActuators(unSegundo);
      expect(p.state.tubo, TubeState.cerrado);
    });

    test('la guillotina tambien recorre en 15 s', () {
      final HydraulicProtocol p = conPeso(1000);

      p.applyMovimiento(abrirGuillotina);
      correrActuadores(p, 15);

      expect(p.state.gillo, 100);
    });

    test('se ignora mientras hay una corrida, incluso abriendo el tubo', () {
      final HydraulicProtocol p = conPeso(1000);
      p.applyInicio(inicio('AT+INICIO=500,300,100,1,2'));

      final String log = p.applyMovimiento(cerrarTubo);

      expect(log, contains('ignorado, hay una descarga en curso'));
      expect(p.state.tubo, TubeState.abriendo, reason: 'sigue el ciclo');
    });
  });

  group('configuracion', () {
    test('sobrevive al reset de la corrida', () {
      final HydraulicProtocol p = conPeso(1000);
      p.setTomaFuerza(HydraulicPtoState.on);
      p.setTomaFuerzaRpm(800);
      p.setErrorEcu('E42');
      p.applyInicio(inicio('AT+INICIO=500,300,100,1,2'));

      p.resetRunState();

      expect(p.state.phase, HydraulicRunPhase.idle);
      expect(p.state.tubo, TubeState.cerrado);
      expect(p.state.gillo, 0);
      // tomaFuerza, rpm y errorEcu son del tester, no de la corrida.
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
      correrActuadores(p, 6);
      expect(p.setPeso(200), isNull, reason: 'no se edita mientras baja');
    });
  });

  group('JSON', () {
    test('lleva tubo y gillo', () {
      final HydraulicProtocol p = conPeso(1000);

      expect(
        p.encodePayload(p.measurement(humidity: 10.0)),
        contains('"tubo":0,"gillo":0'),
      );

      p.applyInicio(inicio('AT+INICIO=500,300,100,1,2'));
      correrActuadores(p, 4);
      expect(
        p.encodePayload(p.measurement(humidity: 10.0)),
        contains('"tubo":2,"gillo":25'),
      );
    });

    test('rpm solo con la toma de fuerza encendida', () {
      final HydraulicProtocol p = conPeso(1000);
      p.setTomaFuerzaRpm(800);

      expect(p.encodePayload(p.measurement(humidity: 10.0)), contains('"rpm":0'));

      p.setTomaFuerza(HydraulicPtoState.on);
      expect(
        p.encodePayload(p.measurement(humidity: 10.0)),
        contains('"rpm":800'),
      );
    });
  });
}
