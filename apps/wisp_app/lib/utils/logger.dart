// Copyright © 2026 wizeshi

/// Centralized logging utility
library;

import 'package:logger/logger.dart';

/// Global logger instance for the application
final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 5,
    lineLength: 80,
    colors: true,
    printEmojis: false,
    dateTimeFormat: DateTimeFormat.onlyTime,
    noBoxingByDefault: true,
  ),
);
