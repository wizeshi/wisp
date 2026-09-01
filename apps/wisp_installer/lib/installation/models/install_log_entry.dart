class InstallLogEntry {
  final DateTime timestamp;
  final String category;
  final String message;

  InstallLogEntry({
    required this.category,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get formattedTimestamp {
    final time = timestamp;
    final hours = time.hour.toString().padLeft(2, '0');
    final minutes = time.minute.toString().padLeft(2, '0');
    final seconds = time.second.toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String get formattedLine => '[$formattedTimestamp] [$category] $message';
}
