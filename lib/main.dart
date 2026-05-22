import 'package:flutter/widgets.dart';
import 'package:test_jaguar/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppBootstrap.run();
}
