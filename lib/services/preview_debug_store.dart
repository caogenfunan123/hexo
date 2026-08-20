/// 预览调试日志存储（环形缓冲，业务无关，只在 debug 或用户明确开启时使用）。
class PreviewDebugStore {
  PreviewDebugStore._();

  static final PreviewDebugStore _instance = PreviewDebugStore._();
  static PreviewDebugStore get instance => _instance;

  static const int _maxLines = 500;

  final List<LogEntry> _entries = [];
  bool _enabled = true;

  bool get enabled => _enabled;
  List<LogEntry> get entries => List.unmodifiable(_entries);

  void enable() => _enabled = true;
  void disable() => _enabled = false;

  void log(String source, String message, {LogLevel level = LogLevel.info}) {
    if (!_enabled) return;
    _entries.add(LogEntry(
      timestamp: DateTime.now(),
      source: source,
      message: message,
      level: level,
    ));
    if (_entries.length > _maxLines) {
      _entries.removeAt(0);
    }
  }

  void clear() => _entries.clear();

  String export() {
    final buf = StringBuffer();
    for (final e in _entries) {
      final t = e.timestamp;
      final ts = '${t.hour}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';
      buf.writeln('[$ts][${e.level.name}][${e.source}] ${e.message}');
    }
    return buf.toString();
  }
}

enum LogLevel { debug, info, warn, error }

class LogEntry {
  final DateTime timestamp;
  final String source;
  final String message;
  final LogLevel level;

  LogEntry({
    required this.timestamp,
    required this.source,
    required this.message,
    required this.level,
  });
}