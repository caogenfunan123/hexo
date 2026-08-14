/// 时间戳 / 速记锚点工具
///
/// 复刻 QuickDaily 的时间戳能力：支持多种格式，可自动插入到锚点位置。
library;

/// 时间戳格式枚举（对应 UiSettings.timestampFormat 存储值）
enum TimestampFormat {
  date,      // 2026-08-14
  time,      // 14:30
  datetime,  // 2026-08-14 14:30
  iso,       // 2026-08-14T14:30:00
  slash,     // 2026/08/14 14:30
  cn,        // 2026年8月14日 14:30
  compact;   // 20260814-1430

  static TimestampFormat fromKey(Object? key) {
    for (final f in TimestampFormat.values) {
      if (f.name == key) return f;
    }
    return TimestampFormat.date;
  }
}

/// 时间戳工具类
class TimestampUtil {
  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// 按格式生成时间戳文本
  static String format(DateTime now, TimestampFormat fmt) {
    switch (fmt) {
      case TimestampFormat.date:
        return '${now.year}-${_pad(now.month)}-${_pad(now.day)}';
      case TimestampFormat.time:
        return '${_pad(now.hour)}:${_pad(now.minute)}';
      case TimestampFormat.datetime:
        return '${now.year}-${_pad(now.month)}-${_pad(now.day)} ${_pad(now.hour)}:${_pad(now.minute)}';
      case TimestampFormat.iso:
        return '${now.year}-${_pad(now.month)}-${_pad(now.day)}T${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}';
      case TimestampFormat.slash:
        return '${now.year}/${_pad(now.month)}/${_pad(now.day)} ${_pad(now.hour)}:${_pad(now.minute)}';
      case TimestampFormat.cn:
        return '${now.year}年${now.month}月${now.day}日 ${_pad(now.hour)}:${_pad(now.minute)}';
      case TimestampFormat.compact:
        return '${now.year}${_pad(now.month)}${_pad(now.day)}-${_pad(now.hour)}${_pad(now.minute)}';
    }
  }

  /// 从字符串 key 格式化
  static String formatKey(String key, {DateTime? now}) {
    return format(now ?? DateTime.now(), TimestampFormat.fromKey(key));
  }
}

/// 速记锚点工具
class QuickNoteTemplate {
  /// 拼接速记草稿初始内容：锚点 + 时间戳 + 用户文本
  ///
  /// [anchor] 锚点文本（如 "## 灵感\n"），时间戳插入到锚点之后。
  static String compose({
    required String anchor,
    required String timestampFormatKey,
    required bool insertTimestamp,
    required String userText,
  }) {
    final buf = StringBuffer();
    if (anchor.isNotEmpty) buf.write(anchor);
    if (insertTimestamp) {
      buf.write(TimestampUtil.formatKey(timestampFormatKey));
      buf.write('\n');
    }
    if (userText.isNotEmpty) {
      buf.write(userText);
      buf.write('\n');
    }
    return buf.toString();
  }
}
