import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

/// A single todo task.
class TodoItem {
  String title;
  bool isDone;

  TodoItem({required this.title, this.isDone = false});
}

/// Centre screen — daily & weekly todo view.
///
/// • Daily view  : shows 5 tasks for the viewed date; navigate day by day.
/// • Weekly view : shows all 7 days of the viewed week as cards; tap to open.
/// • Toggle      : calendar_view_week / view_day icon in the AppBar.
/// • Nav arrows  : ‹ › in the AppBar title row move one day / one week.
/// • "Today"     : shortcut icon resets the view to today.
// ── Task configuration model ─────────────────────────────────────────────

class TaskConfig {
  bool isEditable;
  bool isRepeating;
  bool isRequired;

  TaskConfig({
    required this.isEditable,
    required this.isRepeating,
    required this.isRequired,
  });

  Map<String, dynamic> toJson() => {
        'isEditable': isEditable,
        'isRepeating': isRepeating,
        'isRequired': isRequired,
      };

  factory TaskConfig.fromJson(Map<String, dynamic> json) => TaskConfig(
        isEditable: json['isEditable'] as bool? ?? false,
        isRepeating: json['isRepeating'] as bool? ?? false,
        isRequired: json['isRequired'] as bool? ?? true,
      );

  static List<TaskConfig> defaults() => [
        TaskConfig(isEditable: false, isRepeating: true,  isRequired: true),  // task 1
        TaskConfig(isEditable: false, isRepeating: true,  isRequired: true),  // task 2
        TaskConfig(isEditable: true,  isRepeating: false, isRequired: true),  // task 3
        TaskConfig(isEditable: true,  isRepeating: false, isRequired: true),  // task 4
        TaskConfig(isEditable: true,  isRepeating: false, isRequired: false), // task 5
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// View mode
// ─────────────────────────────────────────────────────────────────────────────

enum _ViewMode { daily, weekly, monthly }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ── Day-of-week schedule for task 1 ──────────────────────────────────────
  static const Map<int, String> _defaultDayTasks = {
    1: 'Rasieren',
    2: 'Pfadfinder',
    3: 'Haare waschen',
    4: 'Rasieren',
    5: 'Botc',
    6: 'Haare waschen',
    7: 'Nächste Woche planen',
  };

  Map<int, String> _dayTasks = Map.of(_HomeScreenState._defaultDayTasks);
  static const String _dayTasksKey = 'day_tasks';

  static const List<String> _weekdayLabels = [
    'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag',
    'Freitag', 'Samstag', 'Sonntag',
  ];

  static const List<String> _weekdayShort = [
    'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So',
  ];

  // ── View state ────────────────────────────────────────────────────────────
  _ViewMode _viewMode = _ViewMode.daily;
  late DateTime _viewedDate;  // date shown in daily view
  late DateTime _weekStart;   // Monday of the displayed week
  late DateTime _monthStart;  // 1st of the displayed month

  /// Lightweight cache used by the weekly view: dateKey → task title previews.
  Map<String, List<String>> _weekCache    = {};
  Map<String, int>           _weekDoneCache = {};
  bool _weekCacheLoading = false;

  /// Cache for the monthly view: dateKey → number of completed tasks (0–5).
  Map<String, int> _monthCache = {};
  bool _monthCacheLoading = false;

  // ── Daily task state ──────────────────────────────────────────────────────
  List<TodoItem> _tasks = [];
  int? _editingIndex;
  List<TextEditingController> _controllers = [];

  // ── Counter ───────────────────────────────────────────────────────────────
  int _counter = 0;
  static const String _counterKey = 'stunden_counter';

  // ── Autocomplete history ──────────────────────────────────────────────
  List<String> _taskHistory = [];

  // ── Task configuration ────────────────────────────────────────────────────
  List<TaskConfig> _taskConfigs = TaskConfig.defaults();
  static const String _taskConfigKey = 'task_config';

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _viewedDate = today;
    _weekStart  = _mondayOf(today);
    _monthStart = DateTime(today.year, today.month, 1);
    _initTasksForDate(today);
    // Wait for both day-tasks and task-config before loading task titles
    // so _isTaskRepeating() and _dayTasks are up-to-date.
    Future.wait([_loadDayTasks(), _loadTaskConfig()])
        .then((_) => _loadTasksForDate(today));
    _maybeDoWeeklyReset();
    _maybeDoAccountabilityCheck();
    _loadTaskHistory();
    _loadCounter();
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _mondayOf(DateTime d) =>
      d.subtract(Duration(days: d.weekday - 1));

  String _taskKey(int n, DateTime date) =>
      'task${n}_${DateFormat('yyyy-MM-dd').format(date)}';

  String _doneKey(int n, DateTime date) =>
      'done${n}_${DateFormat('yyyy-MM-dd').format(date)}';

  static const String _historyKey = 'task_title_history';

  Future<void> _loadTaskHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey) ?? '';
    if (!mounted) return;
    setState(() {
      _taskHistory = raw.isEmpty
          ? []
          : raw.split('|').where((s) => s.isNotEmpty).toList();
    });
  }

  Future<void> _loadDayTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dayTasksKey);
    if (raw == null || !mounted) return;
    try {
      final map = (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(int.parse(k), v as String));
      setState(() => _dayTasks = map);
    } catch (_) {}
  }

  Future<void> _saveDayTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _dayTasksKey,
      jsonEncode(_dayTasks.map((k, v) => MapEntry(k.toString(), v))),
    );
  }

  Future<void> _loadTaskConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_taskConfigKey);
    if (raw == null || !mounted) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final parsed = list.map(TaskConfig.fromJson).toList();
      final defaults = TaskConfig.defaults();
      while (parsed.length < defaults.length) {
        parsed.add(defaults[parsed.length]);
      }
      setState(() {
        _taskConfigs = parsed.take(defaults.length).toList();
      });
    } catch (_) {}
  }

  Future<void> _saveTaskConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _taskConfigKey,
      jsonEncode(_taskConfigs.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> _openSettings() async {
    final result = await showDialog<_SettingsResult>(
      context: context,
      builder: (_) => _TaskSettingsDialog(
        configs: _taskConfigs,
        dayTasks: _dayTasks,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _taskConfigs = result.configs;
        _dayTasks    = result.dayTasks;
      });
      await _saveTaskConfig();
      await _saveDayTasks();
      // Reload tasks so task-1 title and repeating defaults are refreshed.
      if (mounted) await _loadTasksForDate(_viewedDate);
      // Invalidate cached views.
      if (_viewMode == _ViewMode.weekly)  _loadWeekCache(_weekStart);
      if (_viewMode == _ViewMode.monthly) _loadMonthCache(_monthStart);
    }
  }

  Future<void> _loadCounter() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _counter = prefs.getInt(_counterKey) ?? 0);
  }

  Future<void> _saveCounter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_counterKey, _counter);
  }

  Future<void> _saveToHistory(String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    if (_taskHistory.contains(t)) return;
    final updated = [..._taskHistory, t];
    if (mounted) setState(() => _taskHistory = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, updated.join('|'));
  }

  static const String _usageKey = 'task_usage_map';

  Future<void> _recordTaskUsage(String title, DateTime date) async {
    final t = title.trim();
    if (t.isEmpty) return;
    final yearSuffix  = '_${date.year}';
    final monthSuffix = '_${date.year}_${date.month.toString().padLeft(2, '0')}';
    final prefs = await SharedPreferences.getInstance();
    for (final mapKey in [
      _usageKey,
      '$_usageKey$yearSuffix',
      '$_usageKey$monthSuffix',
    ]) {
      final raw = prefs.getString(mapKey) ?? '{}';
      final map = Map<String, int>.from(
        (jsonDecode(raw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as int)),
      );
      map[t] = (map[t] ?? 0) + 1;
      await prefs.setString(mapKey, jsonEncode(map));
    }
  }

  bool get _isToday => _viewedDate == _dateOnly(DateTime.now());
  bool get _isViewedSunday => _viewedDate.weekday == DateTime.sunday;

  TaskConfig _cfgForTask(int n) {
    final i = n - 1;
    if (i >= 0 && i < _taskConfigs.length) return _taskConfigs[i];
    final defaults = TaskConfig.defaults();
    return defaults[i.clamp(0, defaults.length - 1)];
  }

  bool _isTaskRequired(int n) => _cfgForTask(n).isRequired;
  bool _isTaskRepeating(int n) => _cfgForTask(n).isRepeating;

  // ── Task initialisation ───────────────────────────────────────────────────

  /// Rebuilds _tasks + _controllers for [date] (synchronous skeleton).
  void _initTasksForDate(DateTime date) {
    for (final c in _controllers) c.dispose();
    _tasks = [
      TodoItem(title: _dayTasks[date.weekday] ?? ''),
      TodoItem(title: ''),
      TodoItem(title: ''),
      TodoItem(title: ''),
      TodoItem(title: ''),
    ];
    _controllers = List.generate(
      _tasks.length,
      (i) => TextEditingController(text: _tasks[i].title),
    );
    _editingIndex = null;
  }

  /// Fills tasks 2–5 from SharedPreferences (async).
  Future<void> _loadTasksForDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    const defaults = [
      '',
      'Daily report schreiben',
      'Task-Board aktualisieren',
      'Morgen planen',
    ];
    if (!mounted) return;
    setState(() {
      // Task 1: use day schedule, but respect an explicit empty (skipped) save
      final savedTask1 = prefs.getString(_taskKey(1, date));
      if (savedTask1 != null && savedTask1.isEmpty) {
        _tasks[0].title = '';
        _controllers[0].text = '';
      }
      for (int n = 2; n <= 5; n++) {
        final saved = prefs.getString(_taskKey(n, date));
        final value = (saved != null && saved.isNotEmpty)
            ? saved
            : (_isTaskRepeating(n) ? defaults[n - 2] : '');
        _tasks[n - 1].title = value;
        _controllers[n - 1].text = value;
      }
      // Load done states for all tasks
      for (int n = 1; n <= 5; n++) {
        _tasks[n - 1].isDone = prefs.getBool(_doneKey(n, date)) ?? false;
      }
      // Sunday task-1 overrides: auto-complete if all next-week tasks planned
      if (date.weekday == DateTime.sunday) {
        _tasks[0].isDone = _allNextWeekTask2sSaved(prefs, date);
      }
    });
  }

  // ── Date navigation ───────────────────────────────────────────────────────

  void _switchToDate(DateTime date) {
    date = _dateOnly(date);
    setState(() {
      _viewedDate  = date;
      _weekStart   = _mondayOf(date);
      _monthStart  = DateTime(date.year, date.month, 1);
      _viewMode    = _ViewMode.daily;
      _initTasksForDate(date);
    });
    _loadTasksForDate(date);
  }

  void _goToToday() => _switchToDate(_dateOnly(DateTime.now()));

  // ── Weekly view ───────────────────────────────────────────────────────────

  void _enterWeeklyView() {
    setState(() => _viewMode = _ViewMode.weekly);
    _loadWeekCache(_weekStart);
  }

  void _enterMonthlyView() {
    final ms = DateTime(_viewedDate.year, _viewedDate.month, 1);
    setState(() {
      _viewMode   = _ViewMode.monthly;
      _monthStart = ms;
    });
    _loadMonthCache(ms);
  }

  void _navigateMonth(int delta) {
    final ms = DateTime(_monthStart.year, _monthStart.month + delta, 1);
    setState(() => _monthStart = ms);
    _loadMonthCache(ms);
  }

  Future<void> _loadMonthCache(DateTime monthStart) async {
    if (mounted) setState(() => _monthCacheLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final cache = <String, int>{};
    final daysInMonth =
        DateTime(monthStart.year, monthStart.month + 1, 0).day;
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(monthStart.year, monthStart.month, d);
      final key  = DateFormat('yyyy-MM-dd').format(date);
      int done = 0;
      for (int n = 1; n <= 5; n++) {
        if (prefs.getBool(_doneKey(n, date)) == true) done++;
      }
      cache[key] = done;
    }
    if (!mounted) return;
    setState(() {
      _monthCache        = cache;
      _monthCacheLoading = false;
    });
  }

  void _navigateWeek(int delta) {
    final newStart = _weekStart.add(Duration(days: 7 * delta));
    setState(() => _weekStart = newStart);
    _loadWeekCache(newStart);
  }

  Future<void> _loadWeekCache(DateTime weekStart) async {
    if (mounted) setState(() => _weekCacheLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final cache     = <String, List<String>>{};
    final doneCache = <String, int>{};

    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final key  = DateFormat('yyyy-MM-dd').format(date);
      // Task 1: respect explicit saved value (e.g. skipped = empty string)
      final savedTask1 = prefs.getString(_taskKey(1, date));
      final task1Title = (savedTask1 != null)
          ? savedTask1  // empty string means explicitly skipped
          : (_dayTasks[date.weekday] ?? '');
      final titles = <String>[task1Title];
      for (int n = 2; n <= 5; n++) {
        final v = prefs.getString(_taskKey(n, date)) ?? '';
        if (v.isNotEmpty) titles.add(v);
      }
      cache[key] = titles;
      int done = 0;
      for (int n = 1; n <= 5; n++) {
        if (prefs.getBool(_doneKey(n, date)) == true) done++;
      }
      doneCache[key] = done;
    }

    if (!mounted) return;
    setState(() {
      _weekCache        = cache;
      _weekDoneCache    = doneCache;
      _weekCacheLoading = false;
    });
  }

  // ── Sunday planner ────────────────────────────────────────────────────────

  bool _allNextWeekTask2sSaved(SharedPreferences prefs, DateTime sunday) {
    final requiredRepeating = <int>[];
    for (int n = 2; n <= 5; n++) {
      if (_isTaskRepeating(n) && _isTaskRequired(n)) {
        requiredRepeating.add(n);
      }
    }
    // No repeating required tasks configured → the planner is always "done".
    if (requiredRepeating.isEmpty) return true;

    final nextMonday = sunday.add(Duration(days: 8 - sunday.weekday));
    for (int i = 0; i < 7; i++) {
      final date = nextMonday.add(Duration(days: i));
      for (final n in requiredRepeating) {
        if ((prefs.getString(_taskKey(n, date)) ?? '').isEmpty) return false;
      }
    }
    return true;
  }

  Future<void> _openWeeklyPlanner() async {
    final nextMonday =
        _viewedDate.add(Duration(days: 8 - _viewedDate.weekday));
    final prefs = await SharedPreferences.getInstance();

    final planControllers = List.generate(7, (day) {
      return List.generate(4, (offset) {
        final date = nextMonday.add(Duration(days: day));
        return TextEditingController(
          text: prefs.getString(_taskKey(offset + 2, date)) ?? '',
        );
      });
    });

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WeeklyPlannerDialog(
        nextMonday: nextMonday,
        weekdayLabels: _weekdayLabels,
        controllers: planControllers,
        history: _taskHistory,
        taskConfigs: _taskConfigs,
      ),
    );

    if (confirmed == true) {
      for (int day = 0; day < 7; day++) {
        final date = nextMonday.add(Duration(days: day));
        for (int offset = 0; offset < 4; offset++) {
          final taskNumber = offset + 2;
          if (!_isTaskRepeating(taskNumber)) continue;
          final text = planControllers[day][offset].text.trim();
          if (text.isNotEmpty) {
            await prefs.setString(_taskKey(taskNumber, date), text);
            _saveToHistory(text);
          }
        }
      }
      if (mounted) {
        if (_allNextWeekTask2sSaved(prefs, _viewedDate)) {
          setState(() => _tasks[0].isDone = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Nächste Woche gespeichert ✓  —  Task 1 erledigt!'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Gespeichert — fülle alle 7 Aufgaben aus, '
                'um Task 1 automatisch abzuhaken.',
              ),
            ),
          );
        }
      }
    }

    for (final dayCtrls in planControllers) {
      for (final c in dayCtrls) c.dispose();
    }
  }

  // ── Task helpers ──────────────────────────────────────────────────────────

  bool _isEditable(int index) {
    if (index < 0 || index >= _taskConfigs.length) return false;
    return _taskConfigs[index].isEditable;
  }

  void _toggleDone(int index) {
    final today = _dateOnly(DateTime.now());
    if (_viewedDate.isBefore(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vergangene Tage können nicht mehr geändert werden.',
          ),
        ),
      );
      return;
    }
    if (_viewedDate.isAfter(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Zukünftige Aufgaben können noch nicht erledigt werden.',
          ),
        ),
      );
      return;
    }
    if (index == 0 && _isViewedSunday) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Öffne den Wochenplaner (📅) und trage alle 7 Aufgaben ein, '
            'um diesen Task automatisch abzuhaken.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _tasks[index].isDone = !_tasks[index].isDone;
      if (_editingIndex == index) _commitEdit(index);
    });
    // Persist done state
    _saveDoneState(index + 1, _viewedDate, _tasks[index].isDone);
  }

  Future<void> _saveDoneState(int n, DateTime date, bool done) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_doneKey(n, date), done);
  }

  Future<void> _saveTaskTitle(int n, DateTime date, String title) async {
    if (n < 1 || n > 5) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_taskKey(n, date), title);
  }

  Future<void> _clearPastTask(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.not_interested, color: Colors.grey, size: 36),
        title: const Text('Aufgabe überspringen?'),
        content: const Text(
          'Die Aufgabe wird als übersprungen markiert und ihr Inhalt gelöscht.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Überspringen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _tasks[index].title  = '';
      _tasks[index].isDone = false;
    });
    await _saveTaskTitle(index + 1, _viewedDate, '');
    await _saveDoneState(index + 1, _viewedDate, false);
  }

  // ── Weekly reward reset ───────────────────────────────────────────────────

  /// Runs on every app start. If a new week has begun since the last reset,
  /// grants base weekly rewards + a bonus based on how many task-5s were
  /// completed in the week that just ended.
  Future<void> _maybeDoWeeklyReset() async {
    final prefs = await SharedPreferences.getInstance();
    final now = _dateOnly(DateTime.now());
    final currentMonday = _mondayOf(now);
    final currentMondayStr = DateFormat('yyyy-MM-dd').format(currentMonday);
    final lastResetStr = prefs.getString('last_reward_reset');

    // Already reset this week → nothing to do.
    if (lastResetStr == currentMondayStr) return;

    // ── Base weekly rewards ──
    final grants = <String, int>{
      'gaming': 4,
      'youtube': 3,
      'cinema': 2,
      'cake': 2,
      'mystery': 1,
      'skip': 1,
    };

    // ── Bonus from last week's task-5 completions ──
    if (lastResetStr != null) {
      final lastMonday = DateTime.parse(lastResetStr);
      int completions = 0;
      for (int i = 0; i < 7; i++) {
        final date = lastMonday.add(Duration(days: i));
        if (prefs.getBool(_doneKey(5, date)) == true) completions++;
      }
      if (completions >= 7) {
        grants['mystery'] = (grants['mystery'] ?? 0) + 3;
      } else if (completions >= 6) {
        grants['mystery'] = (grants['mystery'] ?? 0) + 2;
      } else if (completions >= 5) {
        grants['mystery'] = (grants['mystery'] ?? 0) + 1;
      } else if (completions >= 4) {
        grants['cake'] = (grants['cake'] ?? 0) + 1;
      } else if (completions >= 3) {
        grants['cinema'] = (grants['cinema'] ?? 0) + 1;
      } else if (completions >= 2) {
        grants['youtube'] = (grants['youtube'] ?? 0) + 1;
      } else if (completions >= 1) {
        grants['skip'] = (grants['skip'] ?? 0) + 1;
      }
    }

    // ── Apply grants ──
    for (final entry in grants.entries) {
      final current = prefs.getInt('reward_${entry.key}') ?? 0;
      await prefs.setInt('reward_${entry.key}', current + entry.value);
    }

    await prefs.setString('last_reward_reset', currentMondayStr);

    // ── Notify ──
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎁 Neue Woche — deine Belohnungen wurden aufgeladen!'),
            duration: Duration(seconds: 4),
          ),
        );
      });
    }
  }

  // ── Daily accountability check ────────────────────────────────────────────

  /// On the first launch of each day, check whether yesterday's mandatory
  /// tasks (1-4) were completed. For every task the user confirms they did
  /// NOT complete, one Skip reward is deducted automatically.
  Future<void> _maybeDoAccountabilityCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final yesterday =
        _dateOnly(DateTime.now()).subtract(const Duration(days: 1));
    final checkKey =
        'accountability_done_${DateFormat('yyyy-MM-dd').format(yesterday)}';

    // Already ran the check for yesterday → skip.
    if (prefs.getBool(checkKey) == true) return;
    await prefs.setBool(checkKey, true);

    // Collect required tasks that are NOT marked done for yesterday.
    const taskDefaults = [
      '', // task 1 comes from day schedule
      'Daily report schreiben',
      'Task-Board aktualisieren',
      'Morgen planen',
    ];
    final missed = <int, String>{};
    for (int n = 1; n <= 5; n++) {
      if (!_isTaskRequired(n)) continue;
      if (prefs.getBool(_doneKey(n, yesterday)) != true) {
        String title;
        if (n == 1) {
          title = _dayTasks[yesterday.weekday] ?? 'Task 1';
        } else {
          final saved = prefs.getString(_taskKey(n, yesterday)) ?? '';
          title = saved.isNotEmpty ? saved : taskDefaults[n - 1];
        }
        missed[n] = title;
      }
    }

    if (missed.isEmpty) {
      // All mandatory tasks were completed — maintain streak.
      await _updateStreak(true);
      return;
    }
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Show the dialog; returns the set of task numbers the user claims
      // they DID actually complete.
      final actuallyDone = await showDialog<Set<int>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AccountabilityDialog(
          missed: missed,
          date: yesterday,
        ),
      );

      if (!mounted) return;
      final stillMissed = missed.keys
          .where((n) => !(actuallyDone?.contains(n) ?? false))
          .toList();

      if (stillMissed.isEmpty) {
        // User confirmed all were done — maintain streak, no penalty.
        await _updateStreak(true);
        return;
      }

      // Check if the skip balance can cover all missed tasks.
      final skipBalance = prefs.getInt('reward_skip') ?? 0;
      final streakMaintained = skipBalance >= stillMissed.length;

      // Deduct one Skip per missed mandatory task.
      await prefs.setInt(
          'reward_skip', (skipBalance - stillMissed.length).clamp(-1, 999));

      // Update streak.
      await _updateStreak(streakMaintained);

      if (mounted) {
        final msg = streakMaintained
            ? '🔒 ${stillMissed.length} Skip(s) verbraucht — '
              'dein Streak bleibt erhalten!'
            : '💪 Streak verloren: zu wenige Skips für '
              '${stillMissed.length} verpasste Task(s).';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });
  }

  Future<void> _updateStreak(bool maintained) async {
    final prefs = await SharedPreferences.getInstance();
    if (maintained) {
      final current = (prefs.getInt('stat_streak_current') ?? 0) + 1;
      await prefs.setInt('stat_streak_current', current);
      final best = prefs.getInt('stat_streak_best') ?? 0;
      if (current > best) await prefs.setInt('stat_streak_best', current);
    } else {
      await prefs.setInt('stat_streak_current', 0);
    }
  }

  void _startEdit(int index) {
    setState(() {
      _editingIndex = index;
      _controllers[index].text = _tasks[index].title;
    });
  }

  Future<void> _commitEdit(int index) async {
    final text       = _controllers[index].text.trim();
    final isOptional = !_isTaskRequired(index + 1);
    final today      = _dateOnly(DateTime.now());
    final isNonToday = _viewedDate != today;

    // Empty required task on a non-today day → ask whether to skip.
    if (text.isEmpty && !isOptional && isNonToday) {
      final skip = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.not_interested, color: Colors.grey, size: 36),
          title: const Text('Aufgabe leer lassen?'),
          content: const Text(
            'Die Aufgabe hat keinen Inhalt.\nMöchtest du sie als übersprungen markieren?',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Weiter bearbeiten'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Überspringen'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (skip != true) return; // keep editing
      setState(() {
        _tasks[index].title  = '';
        _tasks[index].isDone = false;
        _editingIndex        = null;
      });
      await _saveTaskTitle(index + 1, _viewedDate, '');
      await _saveDoneState(index + 1, _viewedDate, false);
      return;
    }

    setState(() {
      if (text.isNotEmpty) {
        _tasks[index].title = text;
      } else if (isOptional) {
        _tasks[index].title  = '';
        _tasks[index].isDone = false;
      }
      _editingIndex = null;
    });
    if (text.isNotEmpty) {
      _saveTaskTitle(index + 1, _viewedDate, text);
      _saveToHistory(text);
      _recordTaskUsage(text, _viewedDate);
    } else if (isOptional) {
      _saveTaskTitle(index + 1, _viewedDate, '');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_editingIndex != null) _commitEdit(_editingIndex!);
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: Colors.deepPurple.shade50,
        appBar: _buildAppBar(),
        body: _viewMode == _ViewMode.weekly
            ? _buildWeeklyBody()
            : _viewMode == _ViewMode.monthly
                ? _buildMonthlyBody()
                : _buildDailyBody(),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  AppBar _buildAppBar() {
    final cs = Theme.of(context).colorScheme;

    String subtitle;
    if (_viewMode == _ViewMode.weekly) {
      subtitle =
          '${DateFormat('dd. MMM').format(_weekStart)} – '
          '${DateFormat('dd. MMM yyyy').format(_weekStart.add(const Duration(days: 6)))}';
    } else if (_viewMode == _ViewMode.monthly) {
      subtitle = DateFormat('MMMM yyyy').format(_monthStart);
    } else {
      subtitle = '${_weekdayShort[_viewedDate.weekday - 1]}, ${DateFormat('dd. MMMM yyyy').format(_viewedDate)}';
    }

    void onLeft() {
      if (_viewMode == _ViewMode.weekly) {
        _navigateWeek(-1);
      } else if (_viewMode == _ViewMode.monthly) {
        _navigateMonth(-1);
      } else {
        _switchToDate(_viewedDate.subtract(const Duration(days: 1)));
      }
    }

    void onRight() {
      if (_viewMode == _ViewMode.weekly) {
        _navigateWeek(1);
      } else if (_viewMode == _ViewMode.monthly) {
        _navigateMonth(1);
      } else {
        _switchToDate(_viewedDate.add(const Duration(days: 1)));
      }
    }

    String leftTip  = _viewMode == _ViewMode.weekly ? 'Vorherige Woche'
                    : _viewMode == _ViewMode.monthly ? 'Vorheriger Monat'
                    : 'Vorheriger Tag';
    String rightTip = _viewMode == _ViewMode.weekly ? 'Nächste Woche'
                    : _viewMode == _ViewMode.monthly ? 'Nächster Monat'
                    : 'Nächster Tag';

    // Always show the 2 modes that are NOT currently active.
    // Order: Tag < Woche < Monat.
    final List<({IconData icon, String label, VoidCallback tap})> viewBtns = [
      if (_viewMode != _ViewMode.daily)
        (icon: Icons.view_day,            label: 'Tag',   tap: () => _switchToDate(_viewedDate)),
      if (_viewMode != _ViewMode.weekly)
        (icon: Icons.calendar_view_week,  label: 'Woche', tap: _enterWeeklyView),
      if (_viewMode != _ViewMode.monthly)
        (icon: Icons.calendar_month,      label: 'Monat', tap: _enterMonthlyView),
    ];

    return AppBar(
      backgroundColor: Colors.deepPurple.shade200,
      centerTitle: true,
      elevation: 0,
      // ── Leading: two view-mode toggle buttons ──
      leadingWidth: 92,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: viewBtns.map((b) => _AppBarLabelButton(
          icon: b.icon,
          label: b.label,
          onTap: b.tap,
        )).toList(),
      ),
      // ── Title with inline ‹ › navigation ──
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: leftTip,
            onPressed: onLeft,
          ),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Aufgaben'),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: rightTip,
            onPressed: onRight,
          ),
        ],
      ),
      // ── Actions: "today" shortcut + settings ──
      actions: [
        if (_viewMode == _ViewMode.daily && !_isToday)
          _AppBarLabelButton(
            icon: Icons.today,
            label: 'Heute',
            onTap: _goToToday,
          ),
        _AppBarLabelButton(
          icon: Icons.settings,
          label: 'Einstellung',
          onTap: _openSettings,
        ),
      ],
    );
  }

  // ── Daily body ────────────────────────────────────────────────────────────

  Widget _buildDailyBody() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _tasks.length + 1,
      itemBuilder: (_, index) {
        if (index < _tasks.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              elevation: 2,
              shadowColor: Colors.deepPurple.withOpacity(0.12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              color: Colors.white,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: _buildTaskTile(index),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _buildStundenCard(),
        );
      },
    );
  }

  Widget _buildStundenCard() {
    final valueColor = _counter < 0
        ? Colors.red.shade600
        : _counter == 0
            ? Colors.grey.shade500
            : Colors.green.shade600;
    final octColor = _counter < 0
        ? Colors.red.shade300
        : _counter == 0
            ? Colors.grey.shade300
            : Colors.green.shade400;

    return Card(
      elevation: 3,
      shadowColor: Colors.deepPurple.withOpacity(0.12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: Colors.white,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Label
            const Text(
              'Stunden',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            // Controls + octagon
            Row(
              children: [
                // Decrement
                _ArrowButton(
                  icon: Icons.arrow_downward_rounded,
                  color: Colors.red.shade400,
                  onTap: () { setState(() => _counter--); _saveCounter(); },
                ),
                const SizedBox(width: 12),
                // Octagonal indicator
                CustomPaint(
                  size: const Size(72, 72),
                  painter: _StundenOctPainter(color: octColor),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: Center(
                      child: Text(
                        '$_counter',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: valueColor,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Increment
                _ArrowButton(
                  icon: Icons.arrow_upward_rounded,
                  color: Colors.green.shade500,
                  onTap: () { setState(() => _counter++); _saveCounter(); },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskTile(int index) {
    final task         = _tasks[index];
    final isEditing    = _editingIndex == index;
    final editable     = _isEditable(index);
    final isEmpty      = task.title.isEmpty;
    final isOptional   = !_isTaskRequired(index + 1);
    final today        = _dateOnly(DateTime.now());
    final isFutureDay  = _viewedDate.isAfter(today);
    final isPastDay    = _viewedDate.isBefore(today);
    final checkboxLocked = !_isToday || (index == 0 && _isViewedSunday);

    // Future required task with no title — prompt to set it.
    if (isFutureDay && isEmpty && !isOptional && !isEditing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          onTap: editable ? () => _startEdit(index) : () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Nutze den Wochenplaner (📅), um zukünftige Aufgaben einzutragen.',
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.edit_calendar_outlined, size: 18, color: Colors.deepPurple.shade300),
                const SizedBox(width: 8),
                Text(
                  editable ? 'Aufgabe für diesen Tag eintragen...' : 'Noch nicht geplant',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.deepPurple.shade300,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Past required task that was skipped — show skip indicator.
    if (isPastDay && isEmpty && !isOptional && !isEditing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const SizedBox(width: 48), // align with checkbox width
            Icon(Icons.fast_forward, size: 18, color: Colors.grey.shade400),
            const SizedBox(width: 8),
            Text(
              'Übersprungen',
              style: TextStyle(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      );
    }

    // Optional tasks that are empty are not yet "tasks" — show a lightweight
    // add-placeholder instead of a full tile with a checkbox.
    if (isOptional && isEmpty && !isEditing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          onTap: editable && !isPastDay ? () => _startEdit(index) : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.add, size: 18, color: Colors.grey.shade400),
                const SizedBox(width: 8),
                Text(
                  'Optionale Aufgabe hinzufügen...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Checkbox
          Tooltip(
            message: isPastDay
                ? 'Vergangene Tage können nicht mehr geändert werden'
                : (checkboxLocked
                    ? 'Wird automatisch abgehakt, wenn der Wochenplan vollständig ist'
                    : ''),
            child: Checkbox(
              value: task.isDone,
              onChanged: checkboxLocked ? null : (_) => _toggleDone(index),
              activeColor:
                  checkboxLocked ? Colors.grey : Colors.deepPurple,
            ),
          ),

          // Label / inline editor
          Expanded(
            child: isEditing
                ? _AutocompleteField(
                    controller: _controllers[index],
                    history: _taskHistory,
                    onSubmitted: (_) => _commitEdit(index),
                  )
                : Text(
                    isEmpty ? '–' : task.title,
                    style: TextStyle(
                      fontSize: 15,
                      decoration: task.isDone
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      color: task.isDone
                          ? Colors.grey
                          : (isEmpty ? Colors.grey.shade400 : null),
                      fontStyle: isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
          ),

          // Sunday planner button (task 1 on Sundays)
          if (index == 0 && _isViewedSunday)
            IconButton(
              icon: const Icon(Icons.calendar_month, size: 18),
              tooltip: 'Nächste Woche planen',
              color: Colors.deepPurple,
              onPressed: _openWeeklyPlanner,
            ),

          // Edit icon (editable tasks on all days)
          if (editable && !isEditing)
            IconButton(
              icon: Icon(
                Icons.edit_outlined,
                size: 18,
                color: _isToday
                    ? Colors.deepPurple.shade300
                    : Colors.grey.shade500,
              ),
              tooltip: 'Task bearbeiten',
              onPressed: () => _startEdit(index),
            ),

          // Skip/clear button — visible on non-today days when the task has content
          if (!_isToday && !isEmpty && !isEditing)
            IconButton(
              icon: Icon(Icons.not_interested,
                  size: 18, color: Colors.grey.shade400),
              tooltip: 'Als übersprungen markieren',
              onPressed: () => _clearPastTask(index),
            ),

          // Confirm edit
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.check, size: 18),
              tooltip: 'Speichern',
              color: Colors.green,
              onPressed: () => _commitEdit(index),
            ),
        ],
      ),
    );
  }

  // ── Completion colour scale ──────────────────────────────────────────────
  /// Returns a background [Color] for [done] completed tasks,
  /// or null when done == 0 (caller keeps its own default colour).
  static Color? _completionColor(int done) {
    switch (done) {
      case 1: return Colors.red.shade800;
      case 2: return Colors.red.shade300;
      case 3: return Colors.amber.shade400;
      case 4: return Colors.lightGreen.shade400;
      case 5: return Colors.green.shade700;
      default: return null;
    }
  }

  // ── Monthly body ──────────────────────────────────────────────────────────

  Widget _buildMonthlyBody() {
    if (_monthCacheLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final today       = _dateOnly(DateTime.now());
    final daysInMonth = DateTime(_monthStart.year, _monthStart.month + 1, 0).day;
    // weekday of the 1st (1=Mon … 7=Sun); offset so grid starts on Monday
    final firstWeekday = _monthStart.weekday; // 1–7
    final leadingEmpty = firstWeekday - 1;    // cells before day 1
    final totalCells   = leadingEmpty + daysInMonth;
    final rowCount     = (totalCells / 7).ceil();
    final cs           = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      child: Column(
        children: [
          // ── Weekday header ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: _weekdayShort.map((label) => Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              )).toList(),
            ),
          ),
          // ── Calendar grid ───────────────────────────────────────────
          for (int row = 0; row < rowCount; row++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(7, (col) {
                final cellIndex = row * 7 + col;
                final dayNum    = cellIndex - leadingEmpty + 1;
                if (dayNum < 1 || dayNum > daysInMonth) {
                  // Empty cell
                  return const Expanded(child: SizedBox(height: 72));
                }
                final date    = DateTime(_monthStart.year, _monthStart.month, dayNum);
                final dateKey = DateFormat('yyyy-MM-dd').format(date);
                final done    = _monthCache[dateKey] ?? 0;
                final isToday  = date == today;
                final isViewed = date == _viewedDate;
                final compColor = _completionColor(done);
                final bgColor = compColor
                    ?? (isToday
                        ? Colors.deepPurple.shade600
                        : isViewed
                            ? Colors.deepPurple.shade100
                            : Colors.white);
                // Text is white on dark backgrounds, dark otherwise.
                final textColor = (compColor != null || isToday)
                    ? Colors.white
                    : cs.onSurface;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => _switchToDate(date),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: (compColor ?? Colors.deepPurple)
                                .withOpacity(isToday ? 0.30 : 0.12),
                            blurRadius: isToday ? 8 : 4,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      child: Text(
                        '$dayNum',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  // ── Weekly body ───────────────────────────────────────────────────────────

  Widget _buildWeeklyBody() {
    if (_weekCacheLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final today = _dateOnly(DateTime.now());
    final cs    = Theme.of(context).colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: 7,
      itemBuilder: (_, i) {
        final date    = _weekStart.add(Duration(days: i));
        final dateKey = DateFormat('yyyy-MM-dd').format(date);
        final tasks     = _weekCache[dateKey] ?? [_dayTasks[date.weekday] ?? ''];
        final done      = _weekDoneCache[dateKey] ?? 0;
        final isToday   = date == today;
        final isViewed  = date == _viewedDate;
        final compColor = _completionColor(done);
        final cardColor = compColor
            ?? (isToday
                ? cs.primaryContainer
                : isViewed
                    ? cs.secondaryContainer
                    : Colors.white);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 2,
          shadowColor: (compColor ?? Colors.deepPurple).withOpacity(0.15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          color: cardColor,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _switchToDate(date),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  // Day label
                  SizedBox(
                    width: 44,
                    child: Column(
                      children: [
                        Text(
                          _weekdayShort[date.weekday - 1],
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isToday ? cs.primary : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  VerticalDivider(
                      width: 1, color: cs.outlineVariant),
                  const SizedBox(width: 10),

                  // Task preview: skip task 1 (index 0), show tasks 2–5 (up to 3)
                  Expanded(
                    child: tasks.length <= 1 ||
                            tasks.skip(1).where((t) => t.isNotEmpty).isEmpty
                        ? Text(
                            'Keine Aufgaben',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                              fontSize: 13,
                            ),
                          )
                        : Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: tasks
                                .skip(1)
                                .where((t) => t.isNotEmpty)
                                .take(3)
                                .map(
                                  (t) => Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: 2),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.circle,
                                            size: 5,
                                            color: Colors.deepPurple),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            t,
                                            style: const TextStyle(
                                                fontSize: 13),
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppBar action button with icon + small label beneath it
// ─────────────────────────────────────────────────────────────────────────────

class _AppBarLabelButton extends StatelessWidget {
  const _AppBarLabelButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 1),
            Text(
              label,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Arrow button for Stunden counter
// ─────────────────────────────────────────────────────────────────────────────

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 24, color: color),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Octagon painter for Stunden indicator
// ─────────────────────────────────────────────────────────────────────────────

class _StundenOctPainter extends CustomPainter {
  const _StundenOctPainter({required this.color});
  final Color color;

  static const int _sides = 8;
  static const double _cornerRadius = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.46;

    final vertices = List.generate(_sides, (i) {
      final angle = (i * 360 / _sides + 22.5) * math.pi / 180;
      return Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
    });

    Offset norm(Offset v) {
      final d = v.distance;
      return d == 0 ? Offset.zero : Offset(v.dx / d, v.dy / d);
    }

    final starts = <Offset>[];
    final ends = <Offset>[];
    for (int i = 0; i < _sides; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % _sides];
      final dir = norm(b - a);
      starts.add(a + dir * _cornerRadius);
      ends.add(b - dir * _cornerRadius);
    }

    final path = Path()..moveTo(starts[0].dx, starts[0].dy);
    for (int i = 0; i < _sides; i++) {
      path.lineTo(ends[i].dx, ends[i].dy);
      final v = vertices[(i + 1) % _sides];
      final s = starts[(i + 1) % _sides];
      path.quadraticBezierTo(v.dx, v.dy, s.dx, s.dy);
    }
    path.close();

    canvas.drawShadow(path, Colors.black26, 3, false);

    // Filled background
    canvas.drawPath(path, Paint()..color = color.withOpacity(0.18));

    // Stroke border
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_StundenOctPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Task Settings Dialog
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Settings return value
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsResult {
  final List<TaskConfig>  configs;
  final Map<int, String>  dayTasks;
  const _SettingsResult({required this.configs, required this.dayTasks});
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings dialog
// ─────────────────────────────────────────────────────────────────────────────

class _TaskSettingsDialog extends StatefulWidget {
  final List<TaskConfig>  configs;
  final Map<int, String>  dayTasks;
  const _TaskSettingsDialog({required this.configs, required this.dayTasks});

  @override
  State<_TaskSettingsDialog> createState() => _TaskSettingsDialogState();
}

class _TaskSettingsDialogState extends State<_TaskSettingsDialog> {
  late List<TaskConfig> _configs;
  late Map<int, TextEditingController> _dayControllers;

  static const List<String> _weekdayNames = [
    'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag',
    'Freitag', 'Samstag', 'Sonntag',
  ];

  @override
  void initState() {
    super.initState();
    // deep copy configs so changes can be cancelled
    _configs = widget.configs
        .map((c) => TaskConfig(
              isEditable: c.isEditable,
              isRepeating: c.isRepeating,
              isRequired: c.isRequired,
            ))
        .toList();
    // one controller per weekday (1–7)
    _dayControllers = {
      for (int wd = 1; wd <= 7; wd++)
        wd: TextEditingController(text: widget.dayTasks[wd] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _dayControllers.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Einstellungen'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Section: Task config ───────────────────────────────
              Text(
                'Aufgaben-Konfiguration',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              // Header row
              Row(
                children: [
                  const Expanded(child: SizedBox()),
                  _HeaderLabel('Bearbeit-\nbar'),
                  _HeaderLabel('Wieder-\nholend'),
                  _HeaderLabel('Pflicht'),
                ],
              ),
              const Divider(height: 1),
              ...List.generate(_configs.length, (i) {
                final cfg = _configs[i];
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Aufgabe ${i + 1}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          _ConfigCheckbox(
                            value: cfg.isEditable,
                            onChanged: (v) =>
                                setState(() => cfg.isEditable = v ?? false),
                          ),
                          _ConfigCheckbox(
                            value: cfg.isRepeating,
                            onChanged: (v) =>
                                setState(() => cfg.isRepeating = v ?? false),
                          ),
                          _ConfigCheckbox(
                            value: cfg.isRequired,
                            onChanged: (v) =>
                                setState(() => cfg.isRequired = v ?? false),
                          ),
                        ],
                      ),
                    ),
                    if (i < _configs.length - 1) const Divider(height: 1),
                  ],
                );
              }),

              // ── Section: Recurring task 1 per weekday ─────────────
              const SizedBox(height: 16),
              Text(
                'Wiederkehrende Aufgabe (Aufgabe 1)',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...List.generate(7, (i) {
                final wd = i + 1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _dayControllers[wd],
                    decoration: InputDecoration(
                      labelText: _weekdayNames[i],
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final dayTasks = {
              for (int wd = 1; wd <= 7; wd++)
                wd: _dayControllers[wd]!.text.trim(),
            };
            Navigator.of(context).pop(
              _SettingsResult(configs: _configs, dayTasks: dayTasks),
            );
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  final String text;
  const _HeaderLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ConfigCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  const _ConfigCheckbox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      child: Checkbox(value: value, onChanged: onChanged),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// Accountability Dialog
// ─────────────────────────────────────────────────────────────────────────────

/// Shows yesterday's uncompleted mandatory tasks (1-4) and lets the user
/// confirm which ones they actually did finish. Returns the set of task
/// numbers the user marks as completed.
class _AccountabilityDialog extends StatefulWidget {
  final Map<int, String> missed; // taskNumber → title
  final DateTime date;

  const _AccountabilityDialog({required this.missed, required this.date});

  @override
  State<_AccountabilityDialog> createState() => _AccountabilityDialogState();
}

class _AccountabilityDialogState extends State<_AccountabilityDialog> {
  late final Set<int> _checked; // tasks the user says they DID complete

  @override
  void initState() {
    super.initState();
    _checked = {};
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEE, dd. MMMM').format(widget.date);
    final missedCount =
        widget.missed.length - _checked.length; // still-unconfirmed

    return AlertDialog(
      icon: const Icon(Icons.assignment_late_outlined,
          color: Colors.orange, size: 36),
      title: const Text('Tages-Check', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gestern ($dateLabel) waren diese Pflicht-Tasks '
            'nicht als erledigt markiert. Hast du sie doch geschafft?',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          ...widget.missed.entries.map((e) {
            final done = _checked.contains(e.key);
            return CheckboxListTile(
              value: done,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Task ${e.key}: ${e.value}',
                style: TextStyle(
                  fontSize: 14,
                  decoration:
                      done ? TextDecoration.lineThrough : null,
                  color: done ? Colors.grey : null,
                ),
              ),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _checked.add(e.key);
                } else {
                  _checked.remove(e.key);
                }
              }),
            );
          }),
          if (missedCount > 0) ...
            [
              const Divider(height: 16),
              Text(
                '⚠️ $missedCount nicht erledigte Task(s) kosten je '
                '1 Skip-Belohnung.',
                style: TextStyle(
                    fontSize: 12, color: Colors.orange.shade700),
              ),
            ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, Set<int>.from(_checked)),
          child: const Text('Bestätigen'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Weekly Planner Dialog
// ─────────────────────────────────────────────────────────────────────────────

/// Shows 7 day-sections, each with:
///   • Task 2 field (required — Save is disabled until all 7 are non-empty).
///   • Tasks 3–5 fields (optional — revealed via a "+ Weitere Aufgaben" button).
///
/// Exposed as a public class so it can be widget-tested directly.
@visibleForTesting
class WeeklyPlannerDialog extends StatefulWidget {
  final DateTime nextMonday;
  final List<String> weekdayLabels;

  /// controllers[day][taskOffset]  taskOffset: 0=task2, 1=task3, 2=task4, 3=task5
  final List<List<TextEditingController>> controllers;

  /// Autocomplete suggestions drawn from the user's task title history.
  final List<String> history;
  final List<TaskConfig>? taskConfigs;

  const WeeklyPlannerDialog({
    required this.nextMonday,
    required this.weekdayLabels,
    required this.controllers,
    this.history = const [],
    this.taskConfigs,
  });

  @override
  State<WeeklyPlannerDialog> createState() => _WeeklyPlannerDialogState();
}

class _WeeklyPlannerDialogState extends State<WeeklyPlannerDialog> {
  late final List<bool> _expanded;
  late final List<int> _requiredOffsets;
  late final List<int> _optionalOffsets;

  TaskConfig _effectiveCfgForTask(int n) {
    if (widget.taskConfigs != null && n - 1 < widget.taskConfigs!.length) {
      return widget.taskConfigs![n - 1];
    }
    // Backward-compatible defaults for tests/direct usage:
    // task2 required repeating, task3-5 optional repeating.
    if (n == 2) {
      return TaskConfig(isEditable: true, isRepeating: true, isRequired: true);
    }
    return TaskConfig(isEditable: true, isRepeating: true, isRequired: false);
  }

  @override
  void initState() {
    super.initState();
    _requiredOffsets = [];
    _optionalOffsets = [];
    for (int offset = 0; offset < 4; offset++) {
      final cfg = _effectiveCfgForTask(offset + 2);
      if (!cfg.isRepeating) continue;
      if (cfg.isRequired) {
        _requiredOffsets.add(offset);
      } else {
        _optionalOffsets.add(offset);
      }
    }

    // Pre-expand days that already have optional tasks saved.
    _expanded = List.generate(
      7,
      (day) => _optionalOffsets.any(
        (offset) => widget.controllers[day][offset].text.isNotEmpty,
      ),
    );

  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nächste Woche planen'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(7, _buildDaySection),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  Widget _buildDaySection(int day) {
    final date = widget.nextMonday.add(Duration(days: day));
    final dayLabel =
        '${widget.weekdayLabels[day]}  (${DateFormat('dd.MM.').format(date)})';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Day heading ──────────────────────────────────────────────────
          Text(
            dayLabel,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 4),

          // ── Required repeating tasks ─────────────────────────────────────
          for (int i = 0; i < _requiredOffsets.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: _AutocompleteField(
                controller: widget.controllers[day][_requiredOffsets[i]],
                history: widget.history,
                labelText: 'Aufgabe ${_requiredOffsets[i] + 2}  *',
                textInputAction: TextInputAction.next,
              ),
            ),

          if (_requiredOffsets.isEmpty)
            Text(
              'Keine wiederholenden Pflichtaufgaben konfiguriert.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),

          // ── Optional repeating tasks ─────────────────────────────────────
          if (_optionalOffsets.isNotEmpty)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _expanded[day]
                  ? Column(
                      key: ValueKey('expanded_$day'),
                      children: [
                        const SizedBox(height: 6),
                        for (int i = 0; i < _optionalOffsets.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _AutocompleteField(
                              controller: widget.controllers[day][_optionalOffsets[i]],
                              history: widget.history,
                              labelText: 'Aufgabe ${_optionalOffsets[i] + 2}  (optional)',
                              textInputAction: i < _optionalOffsets.length - 1
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                            ),
                          ),
                      ],
                    )
                  : Align(
                      key: ValueKey('collapsed_$day'),
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _expanded[day] = true),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text(
                          'Weitere Aufgaben hinzufügen (optional)',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
            ),
          const Divider(height: 20),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Autocomplete text field
// ─────────────────────────────────────────────────────────────────────────────

/// A [TextField] that shows autocomplete suggestions from [history] while
/// the user is typing. Selecting a suggestion fills [controller] in place.
class _AutocompleteField extends StatefulWidget {
  const _AutocompleteField({
    required this.controller,
    required this.history,
    this.labelText,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final List<String> history;
  final String? labelText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_AutocompleteField> createState() => _AutocompleteFieldState();
}

class _AutocompleteFieldState extends State<_AutocompleteField> {
  final FocusNode _focusNode = FocusNode();

  // Tracks the internal fieldController provided by Autocomplete so we can
  // attach/detach our sync listener exactly once per controller instance.
  TextEditingController? _syncedController;

  void _syncToExternal() {
    if (_syncedController != null) {
      widget.controller.text = _syncedController!.text;
    }
  }

  void _attachTo(TextEditingController fc) {
    if (_syncedController == fc) return;
    _syncedController?.removeListener(_syncToExternal);
    _syncedController = fc;
    _syncedController!.addListener(_syncToExternal);
  }

  @override
  void dispose() {
    _syncedController?.removeListener(_syncToExternal);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      // Seed the initial value from the controller.
      initialValue: TextEditingValue(text: widget.controller.text),
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return const [];
        return widget.history.where(
          (s) => s.toLowerCase().contains(query),
        );
      },
      onSelected: (selection) {
        widget.controller.text = selection;
        widget.onSubmitted?.call(selection);
      },
      fieldViewBuilder: (context, fieldController, focusNode, onEditingComplete) {
        // Attach our sync listener to this controller instance.
        _attachTo(fieldController);
        return TextField(
          controller: fieldController,
          focusNode: focusNode,
          autofocus: true,
          textInputAction: widget.textInputAction,
          onSubmitted: (v) {
            // Ensure external controller has the latest text before callback.
            widget.controller.text = v;
            widget.onSubmitted?.call(v);
            onEditingComplete();
          },
          decoration: InputDecoration(
            labelText: widget.labelText,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
                vertical: 6, horizontal: 4),
            border: const OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 15),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final option = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Text(option, style: const TextStyle(fontSize: 14)),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
