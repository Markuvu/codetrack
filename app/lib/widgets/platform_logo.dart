import 'package:flutter/material.dart';

import '../services/api_client.dart';

/// Shared platform styling used across screens.
Color platformColor(String platform) {
  switch (platform) {
    case 'codeforces':
      return const Color(0xFF5C9DFF);
    case 'leetcode':
      return const Color(0xFFFFA116);
    case 'codechef':
      return const Color(0xFFC5854A);
    case 'atcoder':
      return const Color(0xFFB0BEC5);
    case 'gfg':
      return const Color(0xFF4CAF50);
    default:
      return const Color(0xFF9E9E9E);
  }
}

String platformDisplayName(String platform) {
  switch (platform) {
    case 'codeforces':
      return 'Codeforces';
    case 'leetcode':
      return 'LeetCode';
    case 'codechef':
      return 'CodeChef';
    case 'atcoder':
      return 'AtCoder';
    case 'gfg':
      return 'GeeksforGeeks';
    default:
      return platform.isEmpty
          ? 'Other'
          : platform[0].toUpperCase() + platform.substring(1);
  }
}

/// The platform's real logo, served by our backend (/api/logo/<platform>)
/// so Flutter web is not blocked by CORS. Falls back to a colored-initial
/// avatar while loading, offline, or for unknown platforms.
///
/// Set [backdrop] to draw the logo on a light disc - dark logos (e.g.
/// AtCoder's black crest) are otherwise nearly invisible on the dark theme.
class PlatformLogo extends StatelessWidget {
  const PlatformLogo(
    this.platform, {
    super.key,
    this.size = 24,
    this.backdrop = false,
  });

  final String platform;
  final double size;
  final bool backdrop;

  Widget _fallback(double dimension) {
    final color = platformColor(platform);
    return SizedBox(
      width: dimension,
      height: dimension,
      child: CircleAvatar(
        radius: dimension / 2,
        backgroundColor: color.withOpacity(0.18),
        foregroundColor: color,
        child: Text(
          platformDisplayName(platform)[0],
          style: TextStyle(
            fontSize: dimension * 0.45,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inner = backdrop ? size * 0.72 : size;
    final logo = FutureBuilder<String>(
      future: ApiClient().baseUrl(),
      builder: (context, snapshot) {
        final base =
            snapshot.data?.trim().replaceAll(RegExp(r'/+$'), '');
        if (base == null || base.isEmpty) return _fallback(inner);
        return ClipRRect(
          borderRadius: BorderRadius.circular(inner * 0.25),
          child: Image.network(
            '$base/api/logo/$platform',
            width: inner,
            height: inner,
            errorBuilder: (context, error, stackTrace) => _fallback(inner),
          ),
        );
      },
    );
    if (!backdrop) return logo;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFECEFF1),
        shape: BoxShape.circle,
      ),
      child: logo,
    );
  }
}
