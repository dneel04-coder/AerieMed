// Companion driver for integration_test/screenshot_test.dart -- run via:
//   flutter drive --driver=test_driver/integration_test.dart \
//       --target=integration_test/screenshot_test.dart -d <device-id>
// Each binding.takeScreenshot('name') call in the test arrives here as raw
// PNG bytes, which get written to screenshots/<name>.png.
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
      onScreenshot: (String name, List<int> image, [Map<String, Object?>? args]) async {
        final dir = Directory('screenshots');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        await File('screenshots/$name.png').writeAsBytes(image);
        return true;
      },
    );
