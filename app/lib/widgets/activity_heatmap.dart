import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Short platform labels for the per-day breakdown line.
const _kShort = {
  'codeforces': 'CF',
  'leetcode': 'LC',
  'codechef': 'CC',
  'atcoder': 'AC',
  'gfg': 'GFG',
};

/// LeetCode-style contribution calendar that merges submissions from every
/// linked platform into one view: a header with totals (submissions, active
/// days, max streak), then one block per month with the label underneath.
/// Dates are the UTC day buckets reported by the backend. Tap a cell to see
/// that day's per-platform breakdown.
class ActivityHeatmap extends StatefulWidget {
  const ActivityHeatmap({super.key, required this.byPlatform});

  /// platform -> 'yyyy-MM-dd' -> submissions that day.
  final Map<String, Map<String, int>> byPlatform;

  @override
  State<ActivityHeatmap> createState() => _ActivityHeatmapState();
}

class _ActivityHeatmapState extends State<ActivityHeatmap> {
  static const _cell = 11.0;
  static const _gap = 3.0;
  static const _monthGap = 10.0;

  /// Intensity ramp applied to the theme's primary color, dim to bright.
  static const _levelOpacities = [0.3, 0.5, 0.75, 1.0];

  final _scroll = ScrollController();
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    // Start scrolled to the most recent month.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Color _emptyColor(ThemeData theme) =>
      theme.colorScheme.surfaceContainerHighest.withOpacity(0.45);

  Color _cellColor(ThemeData theme, int count, int maxCount) {
    if (count <= 0) return _emptyColor(theme);
    final level = maxCount <= 0
        ? 4
        : ((count * 4) / maxCount).ceil().clamp(1, 4);
    return theme.colorScheme.primary.withOpacity(_levelOpacities[level - 1]);
  }

  Widget _cellFor(ThemeData theme, DateTime date, Map<String, int> totals,
      int maxCount) {
    final count = totals[_key(date)] ?? 0;
    final selected = _selected == date;
    return GestureDetector(
      onTap: () => setState(() => _selected = selected ? null : date),
      child: Container(
        width: _cell,
        height: _cell,
        decoration: BoxDecoration(
          color: _cellColor(theme, count, maxCount),
          borderRadius: BorderRadius.circular(3),
          border: selected
              ? Border.all(color: Colors.white70, width: 1.5)
              : null,
        ),
      ),
    );
  }

  /// One month as its own mini-grid (Mon..Sun rows) with the label below,
  /// like LeetCode's calendar.
  Widget _monthBlock(
    ThemeData theme,
    DateTime month,
    DateTime windowStart,
    DateTime today,
    Map<String, int> totals,
    int maxCount,
    DateFormat monthFmt,
  ) {
    final monthEnd = DateTime.utc(month.year, month.month + 1, 0);
    final first = month.isBefore(windowStart) ? windowStart : month;
    final last = monthEnd.isAfter(today) ? today : monthEnd;
    if (last.isBefore(first)) return const SizedBox.shrink();
    final firstMonday = first.subtract(Duration(days: first.weekday - 1));
    final weekCount = (last.difference(firstMonday).inDays ~/ 7) + 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var w = 0; w < weekCount; w++)
              Padding(
                padding: EdgeInsets.only(
                    right: w == weekCount - 1 ? 0 : _gap),
                child: Column(
                  children: [
                    for (var r = 0; r < 7; r++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: _gap),
                        child: () {
                          final date =
                              firstMonday.add(Duration(days: w * 7 + r));
                          if (date.isBefore(first) || date.isAfter(last)) {
                            return const SizedBox(
                                width: _cell, height: _cell);
                          }
                          return _cellFor(theme, date, totals, maxCount);
                        }(),
                      ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          monthFmt.format(month),
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Merge every platform's counts into one per-day total.
    final totals = <String, int>{};
    widget.byPlatform.forEach((_, days) {
      days.forEach((date, count) {
        totals[date] = (totals[date] ?? 0) + count;
      });
    });

    // The window is the past year ending at today's UTC date (backend
    // buckets days in UTC).
    final nowUtc = DateTime.now().toUtc();
    final today = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final windowStart = today.subtract(const Duration(days: 364));

    // Totals, active days and the longest run of consecutive active days.
    var total = 0;
    var maxCount = 0;
    var activeDays = 0;
    var maxStreak = 0;
    var run = 0;
    for (var d = windowStart;
        !d.isAfter(today);
        d = d.add(const Duration(days: 1))) {
      final count = totals[_key(d)] ?? 0;
      total += count;
      if (count > maxCount) maxCount = count;
      if (count > 0) {
        activeDays++;
        run++;
        if (run > maxStreak) maxStreak = run;
      } else {
        run = 0;
      }
    }

    // Month blocks covering the window, oldest first.
    final months = <DateTime>[];
    var m = DateTime.utc(windowStart.year, windowStart.month, 1);
    final lastMonth = DateTime.utc(today.year, today.month, 1);
    while (!m.isAfter(lastMonth)) {
      months.add(m);
      m = DateTime.utc(m.year, m.month + 1, 1);
    }

    final monthFmt = DateFormat('MMM');
    final boldValue = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: theme.textTheme.bodyLarge?.color,
    );

    Widget? detail;
    if (_selected != null) {
      final key = _key(_selected!);
      final count = totals[key] ?? 0;
      final parts = <String>[];
      widget.byPlatform.forEach((platform, days) {
        final c = days[key] ?? 0;
        if (c > 0) parts.add('${_kShort[platform] ?? platform} $c');
      });
      final dateStr = DateFormat('EEE, MMM d, yyyy').format(_selected!);
      detail = Text(
        count == 0
            ? '$dateStr \u00B7 no submissions'
            : '$dateStr \u00B7 $count submission${count == 1 ? '' : 's'}'
                '${parts.isEmpty ? '' : ' \u00B7 ${parts.join(' \u00B7 ')}'}',
        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: bold totals like LeetCode's calendar.
        Wrap(
          spacing: 14,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$total ',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: 'submissions in the past one year',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Total active days: ',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                  TextSpan(text: '$activeDays', style: boldValue),
                ],
              ),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Max streak: ',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                  TextSpan(text: '$maxStreak', style: boldValue),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < months.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                      right: i == months.length - 1 ? 0 : _monthGap),
                  child: _monthBlock(theme, months[i], windowStart, today,
                      totals, maxCount, monthFmt),
                ),
            ],
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 8),
          detail,
        ],
      ],
    );
  }
}
