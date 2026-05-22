import 'package:flutter/material.dart';

class StatusTile extends StatelessWidget {
  const StatusTile({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(value),
    );
  }
}
