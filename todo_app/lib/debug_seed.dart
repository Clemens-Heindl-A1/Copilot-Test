// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Seeds SharedPreferences with a realistic "end of Friday" state:
///
/// • Mon 21 Apr – Thu 24 Apr 2026: tasks 1-4 all marked done.
/// • No task-5 completions (optional tasks skipped all week).
/// • Streak: current = 4, best = 4.
/// • stat_total_task1-4 = 4 each, task5 = 0.
/// • Weekly reward reset already applied for this week
///   (gaming=4, youtube=3, cinema=2, cake=2, mystery=1, skip=1).
/// • All accountability checks for Mon-Thu already cleared.
/// • task_usage_map: a handful of sample task titles with realistic counts.
///
/// This function is ONLY called in debug builds (guarded in main.dart via
/// `assert`). It is a no-op if the data has already been seeded
/// (checked via the `debug_seeded` key).
Future<void> seedDebugData() async {
  final prefs = await SharedPreferences.getInstance();

  if (prefs.getBool('debug_seeded') == true) return;

  // ── Date helpers ─────────────────────────────────────────────────────────
  String fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // Week Mon 20 Apr – Fri 24 Apr 2026
  final monday    = DateTime(2026, 4, 20);
  final tuesday   = DateTime(2026, 4, 21);
  final wednesday = DateTime(2026, 4, 22);
  final thursday  = DateTime(2026, 4, 23);
  final friday    = DateTime(2026, 4, 24);

  final completedDays = [monday, tuesday, wednesday, thursday];

  // Day-of-week task-1 titles (mirrors home_screen._dayTasks)
  const task1Titles = {
    1: 'Rasieren',
    2: 'Pfadfinder',
    3: 'Haare waschen',
    4: 'Rasieren',
    5: 'Botc',
  };

  // Sample task-2 titles the "user" planned for this week
  final task2Titles = {
    fmt(monday):    'Sport',
    fmt(tuesday):   'Einkaufen',
    fmt(wednesday): 'Sport',
    fmt(thursday):  'Meeting vorbereiten',
    fmt(friday):    'Wochenrückblick',
  };

  // Default task 3-4 titles (mirrors home_screen defaults)
  const task3Default = 'Daily report schreiben';
  const task4Default = 'Task-Board aktualisieren';
  const task5Default = 'Morgen planen';

  // ── Write task text for all 5 days ──────────────────────────────────────
  for (final day in [...completedDays, friday]) {
    final key = fmt(day);
    await prefs.setString('task2_$key', task2Titles[key]!);
    await prefs.setString('task3_$key', task3Default);
    await prefs.setString('task4_$key', task4Default);
    await prefs.setString('task5_$key', task5Default);
  }

  // ── Mark tasks 1-4 done for Mon-Thu ─────────────────────────────────────
  for (final day in completedDays) {
    final key = fmt(day);
    for (int n = 1; n <= 4; n++) {
      await prefs.setBool('done${n}_$key', true);
    }
    // task 5 explicitly NOT done
    await prefs.setBool('done5_$key', false);
  }

  // ── Streak ───────────────────────────────────────────────────────────────
  await prefs.setInt('stat_streak_current', 4);
  await prefs.setInt('stat_streak_best', 4);

  // ── Task completion totals ────────────────────────────────────────────────
  await prefs.setInt('stat_total_task1', 4);
  await prefs.setInt('stat_total_task2', 4);
  await prefs.setInt('stat_total_task3', 4);
  await prefs.setInt('stat_total_task4', 4);
  await prefs.setInt('stat_total_task5', 0);

  // ── Weekly reward reset (this Monday already processed) ──────────────────
  await prefs.setString('last_reward_reset', fmt(monday));
  await prefs.setInt('reward_gaming',   4);
  await prefs.setInt('reward_youtube',  3);
  await prefs.setInt('reward_cinema',   2);
  await prefs.setInt('reward_cake',     2);
  await prefs.setInt('reward_mystery',  1);
  await prefs.setInt('reward_skip',     1);

  // ── Accountability checks already done for Mon-Thu ───────────────────────
  for (final day in completedDays) {
    await prefs.setBool('accountability_done_${fmt(day)}', true);
  }

  // ── Task usage map (sample history for autocomplete + top-5) ─────────────
  final usageMap = <String, int>{
    'Sport':                  8,
    'Einkaufen':              5,
    'Meeting vorbereiten':    4,
    'Wochenrückblick':        3,
    'Lesen':                  3,
    'Arzt Termin':            2,
  };
  await prefs.setString('task_usage_map', jsonEncode(usageMap));

  // ── Autocomplete history ──────────────────────────────────────────────────
  await prefs.setString(
    'task_title_history',
    usageMap.keys.join('|'),
  );

  // ── Mark seeded ──────────────────────────────────────────────────────────
  await prefs.setBool('debug_seeded', true);
  print('[debug_seed] Seed data written successfully.');
}
