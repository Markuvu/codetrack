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

/// GitHub-style contribution calendar that merges submissions from every
/// linked platform into one grid. Dates are the UTC day buckets reported by
/// the backend. Tap a cell to see that day's per-platform breakdown.
class ActivityHeatmap extends StatefulWidget {
  const ActivityHeatmap({super.key, required this.byPlatform, this.weeks = 53});

  /// platform -> 'yyyy-MM-dd' -> submissions that day.
  final Map<String, Map<String, int>> byPlatform;

  /// Number of week columns (53 covers a full year).
  final int weeks;

  @override
  State<ActivityHeatmap> createState() => _ActivityHeatmapState();
}

class _ActivityHeatmapState extends State<ActivityHeatmap> {
  static const _cell = 12.0;
  static const _gap = 3.0;
  static const _col = _cell + _gap;
  static const _levelOpacities = [0.3, 0.5, 0.75, 1.0];

  final _scroll = ScrollController();
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    // Start scrolled to the most recent weeks.
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

  Widget _monthLabel(DateTime start, int w, DateFormat fmt, ThemeData theme) {
    final monday = start.add(Duration(days: w * 7));
    if (w > 0) {
      final prev = start.add(Duration(days: (w - 1) * 7));
      if (prev.month == monday.month) return const SizedBox.shrink();
    }
    return Text(
      fmt.format(monday),
      style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    );
  }

  Widget _cellFor(ThemeData theme, DateTime date, DateTime today,
      Map<String, int> totals, int maxCount) {
    if (date.isAfter(today)) {
      return const SizedBox(width: _cell, height: _cell);
    }
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

    // The grid ends at today's UTC date (backend buckets days in UTC).
    final nowUtc = DateTime.now().toUtc();
    final today = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final start = thisMonday.subtract(Duration(days: 7 * (widget.weeks - 1)));

    var maxCount = 0;
    var total = 0;
    totals.forEach((date, count) {
      final parsed = DateTime.tryParse(date);
      if (parsed == null) return;
      final day = DateTime.utc(parsed.year, parsed.month, parsed.day);
      if (day.isBefore(start) || day.isAfter(today)) return;
      total += count;
      if (count > maxCount) maxCount = count;
    });

    final monthFmt = DateFormat('MMM');
    const dayLabels = {0: 'Mon', 2: 'Wed', 4: 'Fri'};

    final labelColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(height: 14),
        for (var r = 0; r < 7; r++)
          SizedBox(
            height: _cell + _gap,
            width: 26,
            child: Text(
              dayLabels[r] ?? '',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 8),
              textAlign: TextAlign.right,
            ),
          ),
      ],
    );

    final grid = SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 14,
            child: Row(
              children: [
                for (var w = 0; w < widget.weeks; w++)
                  SizedBox(
                    width: _col,
                    child: _monthLabel(start, w, monthFmt, theme),
                  ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var w = 0; w < widget.weeks; w++)
                Padding(
                  padding: const EdgeInsets.only(right: _gap),
                  child: Column(
                    children: [
                      for (var r = 0; r < 7; r++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: _gap),
                          child: _cellFor(
                            theme,
                            start.add(Duration(days: w * 7 + r)),
                            today,
                            totals,
                            maxCount,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labelColumn,
            const SizedBox(width: 6),
            Expanded(child: grid),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '$total submissions in the last year',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ),
            Text(
              'Less ',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
            ),
            for (var i = 0; i <= 4; i++)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: i == 0
                        ? _emptyColor(theme)
                        : theme.colorScheme.primary
                            .withOpacity(_levelOpacities[i - 1]),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Text(
              '  More',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
            ),
          ],
        ),
        if (detail != null) ...[
          const SizedBox(height: 6),
          detail,
        ],
      ],
    );
  }
}
