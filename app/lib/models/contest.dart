class Contest {
  final String id;
  final String platform;
  final String name;
  final DateTime start;
  final Duration duration;
  final String url;

  Contest({
    required this.id,
    required this.platform,
    required this.name,
    required this.start,
    required this.duration,
    required this.url,
  });

  factory Contest.fromJson(Map<String, dynamic> json) {
    final startsAt = (json['startsAt'] as num?)?.toInt() ?? 0;
    return Contest(
      id: '${json['id']}',
      platform: json['platform'] as String? ?? '',
      name: json['name'] as String? ?? 'Contest',
      start: DateTime.fromMillisecondsSinceEpoch(startsAt * 1000, isUtc: true),
      duration: Duration(seconds: (json['durationSeconds'] as num?)?.toInt() ?? 0),
      url: json['url'] as String? ?? '',
    );
  }
}
