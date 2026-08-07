/// 写作任务：管理从选题到发布的完整写作流程。
///
/// 状态机：
///   topic（选题）→ outline（提纲）→ writing（草稿）→ published（已发布）
/// 每个任务可携带选题描述、提纲、草稿内容，并关联到已生成的文章。

/// 写作任务状态
enum WritingTaskStatus {
  topic,     // 选题阶段
  outline,   // 提纲阶段
  writing,   // 草稿阶段
  published; // 已发布

  /// 从字符串解析
  static WritingTaskStatus fromName(String? s) {
    switch (s) {
      case 'topic':
        return WritingTaskStatus.topic;
      case 'outline':
        return WritingTaskStatus.outline;
      case 'writing':
        return WritingTaskStatus.writing;
      case 'published':
        return WritingTaskStatus.published;
      default:
        return WritingTaskStatus.topic;
    }
  }
}

extension WritingTaskStatusX on WritingTaskStatus {
  String get label => switch (this) {
        WritingTaskStatus.topic => '选题',
        WritingTaskStatus.outline => '提纲',
        WritingTaskStatus.writing => '草稿',
        WritingTaskStatus.published => '已发布',
      };

  /// 下一阶段
  WritingTaskStatus? get next => switch (this) {
        WritingTaskStatus.topic => WritingTaskStatus.outline,
        WritingTaskStatus.outline => WritingTaskStatus.writing,
        WritingTaskStatus.writing => WritingTaskStatus.published,
        WritingTaskStatus.published => null,
      };

  bool get isTerminal => this == WritingTaskStatus.published;
}

/// 写作任务实体
class WritingTask {
  final String id;
  String title;
  String topic;          // 选题说明
  String outline;        // 提纲
  String draft;          // 草稿内容
  String articleId;      // 关联的文章 ID（可为空）
  WritingTaskStatus status;
  final DateTime createdAt;
  DateTime updatedAt;

  WritingTask({
    required this.id,
    required this.title,
    this.topic = '',
    this.outline = '',
    this.draft = '',
    this.articleId = '',
    this.status = WritingTaskStatus.topic,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'topic': topic,
        'outline': outline,
        'draft': draft,
        'articleId': articleId,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory WritingTask.fromJson(Map<String, dynamic> j) => WritingTask(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        topic: j['topic']?.toString() ?? '',
        outline: j['outline']?.toString() ?? '',
        draft: j['draft']?.toString() ?? '',
        articleId: j['articleId']?.toString() ?? '',
        status: WritingTaskStatus.fromName(j['status']?.toString()),
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(j['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      );

  WritingTask copyWith({
    String? title,
    String? topic,
    String? outline,
    String? draft,
    String? articleId,
    WritingTaskStatus? status,
  }) {
    return WritingTask(
      id: id,
      title: title ?? this.title,
      topic: topic ?? this.topic,
      outline: outline ?? this.outline,
      draft: draft ?? this.draft,
      articleId: articleId ?? this.articleId,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
