class PlatformProfile {
  final String platform;
  final String handle;
  final int? rating;
  final int? solvedCount;
  final Map<String, dynamic> raw;

  PlatformProfile({
    required this.platform,
    required this.handle,
    this.rating,
    this.solvedCount,
    this.raw = const {},
  });

  factory PlatformProfile.fromJson(Map<String, dynamic> json) {
    int? asInt(dynamic v) {
      if (v is num) return v.round();
      return int.tryParse('$v');
    }

    return PlatformProfile(
      platform: json['platform'] as String? ?? 'unknown',
      handle: json['handle'] as String? ?? '',
      rating: asInt(json['rating']),
      solvedCount: asInt(json['solvedCount']),
      raw: json,
    );
  }
}
