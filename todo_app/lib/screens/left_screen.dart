import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ───────────────────────────────────────────────────────────────────────────────
// Period filter
// ───────────────────────────────────────────────────────────────────────────────

enum _Period { lifetime, year, month }

extension _PeriodX on _Period {
  String get keySuffix {
    final now = DateTime.now();
    switch (this) {
      case _Period.lifetime:
        return '';
      case _Period.year:
        return '_${now.year}';
      case _Period.month:
        return '_${now.year}_${now.month.toString().padLeft(2, '0')}';
    }
  }

  String get label {
    switch (this) {
      case _Period.lifetime: return 'Gesamt';
      case _Period.year:     return 'Dieses Jahr';
      case _Period.month:    return 'Dieser Monat';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats model
// ─────────────────────────────────────────────────────────────────────────────

class _Stats {
  final int streakCurrent;
  final int streakBest;
  final List<int> taskTotals;                  // index 0 = task 1 … index 4 = task 5
  final List<MapEntry<String, int>> topTasks;  // top-5 task titles by usage

  const _Stats({
    required this.streakCurrent,
    required this.streakBest,
    required this.taskTotals,
    required this.topTasks,
  });

  /// Derives all stats by scanning the raw `done{n}_{date}` and
  /// `task{n}_{date}` keys in SharedPreferences.  This means every change
  /// to past/future tasks is immediately reflected without any separate
  /// counter bookkeeping.
  static Future<_Stats> load(_Period period) async {
    final prefs = await SharedPreferences.getInstance();
    final now   = DateTime.now();

    // ── Determine the date window for the selected period ──────────────────
    DateTime? windowStart; // null = no lower bound (lifetime)
    DateTime? windowEnd;   // null = no upper bound (lifetime)
    if (period == _Period.year) {
      windowStart = DateTime(now.year, 1, 1);
      windowEnd   = DateTime(now.year, 12, 31);
    } else if (period == _Period.month) {
      windowStart = DateTime(now.year, now.month, 1);
      windowEnd   = DateTime(now.year, now.month + 1, 0); // last day of month
    }

    bool _inWindow(DateTime d) {
      if (windowStart != null && d.isBefore(windowStart)) return false;
      if (windowEnd   != null && d.isAfter(windowEnd))   return false;
      return true;
    }

    // ── Scan all keys once ─────────────────────────────────────────────────
    final taskTotals = List<int>.filled(5, 0);
    final usageMap   = <String, int>{};

    final allKeys = prefs.getKeys();
    // done keys look like:  done{n}_{yyyy-MM-dd}
    final donePattern = RegExp(r'^done(\d+)_(\d{4}-\d{2}-\d{2})$');
    // task title keys:      task{n}_{yyyy-MM-dd}
    final taskPattern = RegExp(r'^task(\d+)_(\d{4}-\d{2}-\d{2})$');

    // Build a map of dateKey → {n → title} for completed tasks so we can
    // populate the top-tasks chart without a second prefs pass.
    final completedTitles = <String, Map<int, String>>{};

    for (final key in allKeys) {
      final m = donePattern.firstMatch(key);
      if (m == null) continue;
      if (prefs.getBool(key) != true) continue;

      final n    = int.tryParse(m.group(1)!) ?? 0;
      final date = DateTime.tryParse(m.group(2)!);
      if (date == null || n < 1 || n > 5) continue;
      if (!_inWindow(date)) continue;

      taskTotals[n - 1]++;

      // Only tasks 2-5 have free-text titles tracked in the top-tasks chart.
      if (n >= 2) {
        final dateKey = m.group(2)!;
        completedTitles.putIfAbsent(dateKey, () => {})[n] = '';
      }
    }

    // Fill in titles for completed task slots.
    for (final key in allKeys) {
      final m = taskPattern.firstMatch(key);
      if (m == null) continue;
      final n       = int.tryParse(m.group(1)!) ?? 0;
      final dateKey = m.group(2)!;
      if (!completedTitles.containsKey(dateKey)) continue;
      if (!completedTitles[dateKey]!.containsKey(n)) continue;
      final title = prefs.getString(key)?.trim() ?? '';
      if (title.isNotEmpty) completedTitles[dateKey]![n] = title;
    }

    // Tally titles into the usage map.
    for (final dayMap in completedTitles.values) {
      for (final title in dayMap.values) {
        if (title.isNotEmpty) usageMap[title] = (usageMap[title] ?? 0) + 1;
      }
    }

    final sorted = usageMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sorted.take(5).toList();

    return _Stats(
      // Streak is always lifetime — not period-specific.
      streakCurrent: prefs.getInt('stat_streak_current') ?? 0,
      streakBest:    prefs.getInt('stat_streak_best')    ?? 0,
      taskTotals:    taskTotals,
      topTasks:      top5,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

/// Stats page – reached by swiping right-to-left on the home screen.
class LeftScreen extends StatefulWidget {
  const LeftScreen({super.key});

  @override
  State<LeftScreen> createState() => _LeftScreenState();
}

class _LeftScreenState extends State<LeftScreen> {
  _Stats? _stats;
  bool _loading = true;
  _Period _period = _Period.lifetime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stats = await _Stats.load(_period);
    if (mounted) setState(() { _stats = stats; _loading = false; });
  }

  Future<void> _resetStats() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.delete_forever, color: Colors.red, size: 36),
        title: const Text('Statistiken zurücksetzen?'),
        content: const Text(
          'Alle erledigten Aufgaben und der Streak werden gelöscht. '
          'Dieser Vorgang kann nicht rückgängig gemacht werden.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zurücksetzen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    // Remove all done keys (done{n}_{date}) and streak counters.
    final toRemove = prefs.getKeys()
        .where((k) => RegExp(r'^done\d+_\d{4}-\d{2}-\d{2}$').hasMatch(k) ||
                      k.startsWith('stat_streak') ||
                      k.startsWith('stat_total_task') ||
                      k.startsWith('task_usage_map') ||
                      k == 'debug_seeded')
        .toList();
    for (final k in toRemove) {
      await prefs.remove(k);
    }
    _load();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo.shade50,
      appBar: AppBar(
        title: const Text('Statistiken'),
        centerTitle: true,
        backgroundColor: Colors.indigo.shade200,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Statistiken zurücksetzen',
            onPressed: _resetStats,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                children: [
                  _buildPeriodToggle(),
                  const SizedBox(height: 16),
                  _buildStreakCard(),
                  const SizedBox(height: 20),
                  _buildTaskTotalsCard(),
                  const SizedBox(height: 20),
                  _buildTopTasksCard(),
                ],
              ),
            ),
    );
  }

  // ── Period toggle ─────────────────────────────────────────────────────────

  Widget _buildPeriodToggle() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: _Period.values.map((p) {
            final selected = p == _period;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.indigo.shade400
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: InkWell(
                    onTap: () {
                      if (_period == p) return;
                      setState(() => _period = p);
                      _load();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      child: Text(
                        p.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : Colors.indigo.shade400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Streak card ───────────────────────────────────────────────────────────

  Widget _buildStreakCard() {
    final s = _stats!;
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department,
                    color: Colors.orange.shade600, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Streak',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatBox(
                    label: 'Aktueller Streak',
                    value: '${s.streakCurrent}',
                    unit: 'Tage',
                    icon: Icons.local_fire_department,
                    iconColor: s.streakCurrent > 0
                        ? Colors.orange.shade500
                        : Colors.grey,
                    valueColor: s.streakCurrent > 0
                        ? Colors.orange.shade700
                        : Colors.grey,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatBox(
                    label: 'Bester Streak',
                    value: '${s.streakBest}',
                    unit: 'Tage',
                    icon: Icons.emoji_events,
                    iconColor: Colors.amber.shade600,
                    valueColor: cs.primary,
                  ),
                ),
              ],
            ),
            if (s.streakCurrent > 0) ...[
              const SizedBox(height: 12),
              _StreakBar(current: s.streakCurrent, best: s.streakBest),
            ],
          ],
        ),
      ),
    );
  }

  // ── Task totals card ──────────────────────────────────────────────────────

  Widget _buildTaskTotalsCard() {
    final s = _stats!;
    final total = s.taskTotals.fold(0, (a, b) => a + b);

    const labels = [
      'Default Task',
      'Wochen Task',
      'Tages Task',
      'Haushalts Task',
      'Bonusaufgabe',
    ];
    const icons = [
      Icons.star_outline,
      Icons.task_alt,
      Icons.description_outlined,
      Icons.dashboard_customize_outlined,
      Icons.add_task,
    ];
    const colors = [
      Colors.deepPurple,
      Colors.indigo,
      Colors.teal,
      Colors.blue,
      Colors.green,
    ];

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart, color: Colors.indigo.shade400, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Erledigte Aufgaben',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  'Gesamt (${ _period.label}): $total',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < 5; i++) ...[
              _TaskBar(
                label: 'Stufe ${i + 1} — ${labels[i]}',
                count: s.taskTotals[i],
                maxCount: total == 0 ? 1 : total,
                icon: icons[i],
                color: colors[i],
              ),
              if (i < 4) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  // ── Top tasks card ────────────────────────────────────────────────────────

  Widget _buildTopTasksCard() {
    final top = _stats!.topTasks;
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.leaderboard,
                    color: Colors.deepPurple.shade400, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Häufigste Aufgaben (Top 5)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _period.label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 14),
            if (top.isEmpty)
              Text(
                'Noch keine Daten — erledige ein paar Aufgaben!',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              )
            else
              for (int i = 0; i < top.length; i++) ...[
                _TopTaskRow(
                  rank: i + 1,
                  title: top[i].key,
                  count: top[i].value,
                  maxCount: top[0].value,
                ),
                if (i < top.length - 1) const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.iconColor,
    required this.valueColor,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color iconColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
          Text(
            unit,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _StreakBar extends StatelessWidget {
  const _StreakBar({required this.current, required this.best});
  final int current;
  final int best;

  @override
  Widget build(BuildContext context) {
    final ratio = best == 0 ? 1.0 : (current / best).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$current / $best Tage (bester Streak)',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            color: Colors.orange.shade400,
            backgroundColor: Colors.orange.shade100,
          ),
        ),
      ],
    );
  }
}

class _TaskBar extends StatelessWidget {
  const _TaskBar({
    required this.label,
    required this.count,
    required this.maxCount,
    required this.icon,
    required this.color,
  });

  final String label;
  final int count;
  final int maxCount;
  final IconData icon;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    final ratio = (count / maxCount).clamp(0.0, 1.0);
    return Row(
      children: [
        Icon(icon, size: 18, color: color.shade500),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(
                    '$count×',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: color.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 7,
                  color: color.shade400,
                  backgroundColor: color.shade100,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TopTaskRow
// ─────────────────────────────────────────────────────────────────────────────

class _TopTaskRow extends StatelessWidget {
  const _TopTaskRow({
    required this.rank,
    required this.title,
    required this.count,
    required this.maxCount,
  });

  final int rank;
  final String title;
  final int count;
  final int maxCount;

  static const _medals = ['🥇', '🥈', '🥉'];
  static const _rankColors = [Colors.amber, Colors.blueGrey, Colors.brown];

  @override
  Widget build(BuildContext context) {
    final ratio = maxCount == 0 ? 0.0 : count / maxCount;
    final medal = rank <= 3 ? _medals[rank - 1] : '#$rank';
    final barColor =
        rank <= 3 ? _rankColors[rank - 1] : Colors.deepPurple.shade300;

    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(medal,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${count}×',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: rank <= 3
                          ? _rankColors[rank - 1]
                          : Colors.deepPurple.shade400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  color: barColor,
                  backgroundColor: Colors.grey.shade200,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
