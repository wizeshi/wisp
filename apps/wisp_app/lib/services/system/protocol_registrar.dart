// Copyright © 2026 wizeshi

import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

class ProtocolRegistrar {
  static Future<bool> isRegistered(String scheme) async {
    String? executablePath = Platform.resolvedExecutable;

    if (Platform.isWindows) {
      RegistryKey? key;
      RegistryKey? commandKey;
      try {
        key = CURRENT_USER.open(
          'Software\\Classes\\$scheme',
          config: RegistryOpenConfig(
            create: false,
            access: RegistryAccess.read,
          ),
        );

        final firstValue = key.getString('');

        final hasURLValue =
            firstValue != null && firstValue.startsWith('URL:$scheme');

        commandKey = key.open(
          'shell\\open\\command',
          config: RegistryOpenConfig(
            create: false,
            access: RegistryAccess.read,
          ),
        );

        final isCorrectExecutable =
            commandKey.getString('') == '"$executablePath" "%1"';

        return hasURLValue && isCorrectExecutable;
      } catch (e) {
        return false;
      } finally {
        commandKey?.close();
        key?.close();
      }
    }

    return false;
  }

  static Future<void> register({
    required String scheme,
    String? executablePath,
  }) async {
    executablePath ??= Platform.resolvedExecutable;

    if (Platform.isWindows) {
      RegistryKey? initialKey;
      RegistryKey? key;
      try {
        initialKey = CURRENT_USER.create('Software\\Classes\\$scheme');

        initialKey.setValue('', RegistryValue.string("URL:$scheme"));

        initialKey.setValue("URL Protocol", RegistryValue.string(''));

        key = initialKey.create("shell\\open\\command");
        key.setValue('', RegistryValue.string('"$executablePath" "%1"'));
      } finally {
        key?.close();
        initialKey?.close();
      }
    }
  }

  static Future<void> unregister(String scheme) async {
    if (Platform.isWindows) {
      CURRENT_USER.removeSubkey('Software\\Classes\\$scheme');
    }
  }
}
