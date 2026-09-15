import 'package:flutter/material.dart';

/// Tarjeta grande con el peso actual. Es puramente presentacional: los chips y
/// el pie los arma cada protocolo, porque cada uno muestra cosas distintas
/// (Jaguar el slider de humedad, el ST407 una nota sobre la cabecera binaria,
/// Manual una aclaracion). Antes preguntaba por el protocolo adentro.
class HeroWeightCard extends StatelessWidget {
  const HeroWeightCard({
    required this.weight,
    this.badges = const <Widget>[],
    this.footer,
    super.key,
  });

  final int weight;

  /// Chips de estado bajo el peso. Cada protocolo arma los suyos.
  final List<Widget> badges;

  /// Lo que va debajo de los chips: un slider, una nota, o nada.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF0D5A5D), Color(0xFF1E8C74)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF1E8C74).withValues(alpha: 0.34),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Peso actual',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  letterSpacing: 0.6,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '$weight kg',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
          ),
          const SizedBox(height: 10),
          if (badges.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: badges),
          if (footer != null) ...<Widget>[
            const SizedBox(height: 12),
            footer!,
          ],
        ],
      ),
    );
  }
}

class HeroBadge extends StatelessWidget {
  const HeroBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
