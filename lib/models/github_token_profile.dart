class GithubTokenProfile {
  final String id;
  final String name;
  final String token;
  final String login;
  final String avatarUrl;
  final String htmlUrl;
  final DateTime? lastVerifiedAt;

  const GithubTokenProfile({
    required this.id,
    required this.name,
    required this.token,
    this.login = '',
    this.avatarUrl = '',
    this.htmlUrl = '',
    this.lastVerifiedAt,
  });

  GithubTokenProfile copyWith({
    String? id,
    String? name,
    String? token,
    String? login,
    String? avatarUrl,
    String? htmlUrl,
    DateTime? lastVerifiedAt,
  }) {
    return GithubTokenProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      token: token ?? this.token,
      login: login ?? this.login,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      htmlUrl: htmlUrl ?? this.htmlUrl,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'token': token,
        'login': login,
        'avatarUrl': avatarUrl,
        'htmlUrl': htmlUrl,
        'lastVerifiedAt': lastVerifiedAt?.toIso8601String(),
      };

  factory GithubTokenProfile.fromJson(Map<String, dynamic> j) {
    return GithubTokenProfile(
      id: j['id']?.toString() ??
          'gh_${DateTime.now().millisecondsSinceEpoch}',
      name: j['name']?.toString() ?? 'GitHub Token',
      token: j['token']?.toString() ?? '',
      login: j['login']?.toString() ?? '',
      avatarUrl: j['avatarUrl']?.toString() ?? '',
      htmlUrl: j['htmlUrl']?.toString() ?? '',
      lastVerifiedAt: DateTime.tryParse(j['lastVerifiedAt']?.toString() ?? ''),
    );
  }

  String get maskedToken {
    final t = token.trim();
    if (t.isEmpty) return '未填写';
    if (t.length <= 8) return '****';
    return '${t.substring(0, 4)}…${t.substring(t.length - 4)}';
  }

  String get displayLabel {
    if (login.isNotEmpty) {
      final n = name.isNotEmpty && name != login ? name : login;
      return n == login ? '@$login' : '$n · @$login';
    }
    if (name.isNotEmpty) return name;
    return maskedToken;
  }
}
