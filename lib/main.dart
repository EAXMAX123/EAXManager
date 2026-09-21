import 'package:flutter/material.dart';

import 'state/app_services.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppServices.I.init();
  runApp(const JmReaderApp());
}
