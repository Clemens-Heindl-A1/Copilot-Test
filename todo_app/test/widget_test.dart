import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:todo_app/main.dart';
import 'package:todo_app/screens/home_screen.dart';
import 'package:todo_app/screens/left_screen.dart';
import 'package:todo_app/screens/right_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── App shell ─────────────────────────────────────────────────────────────
  group('TodoApp', () {
    testWidgets('app launches without crashing', (tester) async {
      await tester.pumpWidget(const TodoApp());
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('SwipeNavigator renders a PageView', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SwipeNavigator()));
      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('HomeScreen is shown on launch', (tester) async {
      await tester.pumpWidget(const TodoApp());
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  // ── Layout ────────────────────────────────────────────────────────────────
  group('HomeScreen — layout', () {
    testWidgets('shows "My Tasks" title', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('My Tasks'), findsOneWidget);
    });

    testWidgets('renders exactly 5 checkboxes in daily view', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(5));
    });

    testWidgets('all 5 tasks start unchecked', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      for (final cb in tester.widgetList<Checkbox>(find.byType(Checkbox))) {
        expect(cb.value, isFalse);
      }
    });

    testWidgets('tasks 1-2 have no edit icon — exactly 3 edit icons shown',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.edit), findsNWidgets(3));
    });

    testWidgets('AppBar contains prev/next chevrons', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('view-toggle button is present', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.calendar_view_week), findsOneWidget);
    });
  });

  // ── Day-of-week schedule ──────────────────────────────────────────────────
  group('HomeScreen — task 1 day schedule', () {
    testWidgets('task 1 matches the day-of-week schedule', (tester) async {
      const schedule = {
        1: 'Rasieren', 2: 'Pfadfinder', 3: 'Haare waschen',
        4: 'Rasieren', 5: 'Botc', 6: 'Haare waschen',
        7: 'Nächste Woche planen',
      };
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text(schedule[DateTime.now().weekday]!), findsOneWidget);
    });
  });

  // ── Prefs loading ─────────────────────────────────────────────────────────
  group('HomeScreen — prefs loading', () {
    testWidgets('task 2 displays value saved for today', (tester) async {
      final today = DateTime.now();
      final key = 'task2_${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      SharedPreferences.setMockInitialValues({key: 'Saved task zwei'});
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Saved task zwei'), findsOneWidget);
    });

    testWidgets('tasks 3-5 show values saved in prefs for today',
        (tester) async {
      final today = DateTime.now();
      String key(int n) => 'task${n}_${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      SharedPreferences.setMockInitialValues({
        key(3): 'Task drei', key(4): 'Task vier', key(5): 'Task fünf',
      });
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Task drei'), findsOneWidget);
      expect(find.text('Task vier'), findsOneWidget);
      expect(find.text('Task fünf'), findsOneWidget);
    });
  });

  // ── Check-off ─────────────────────────────────────────────────────────────
  group('HomeScreen — check-off', () {
    testWidgets('checking task 3 applies strikethrough', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pump();
      final text = tester.widget<Text>(find.text('Daily report schreiben'));
      expect(text.style?.decoration, TextDecoration.lineThrough);
    });
  });

  // ── Inline editing ────────────────────────────────────────────────────────
  group('HomeScreen — inline editing (tasks 3-5)', () {
    testWidgets('tapping edit opens a TextField', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit).first);
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('confirming edit saves the new title', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit).first);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Neuer Titel');
      await tester.tap(find.byIcon(Icons.check));
      await tester.pump();
      expect(find.text('Neuer Titel'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });

  // ── View toggle ───────────────────────────────────────────────────────────
  group('HomeScreen — view toggle', () {
    testWidgets('tapping toggle switches to weekly view', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_view_week));
      await tester.pumpAndSettle();

      // In weekly view the toggle icon flips to view_day.
      expect(find.byIcon(Icons.view_day), findsOneWidget);
      // Checkboxes from daily view are gone; week cards appear instead.
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('tapping toggle again returns to daily view', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_view_week));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.view_day));
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNWidgets(5));
    });
  });

  // ── Day navigation ────────────────────────────────────────────────────────
  group('HomeScreen — day navigation', () {
    testWidgets('tapping chevron_right advances one day', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final expectedDay = tomorrow.day.toString();

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      // The subtitle in the AppBar should contain tomorrow's day number.
      expect(find.textContaining(expectedDay), findsWidgets);
      // "Today" button should now be visible since we are no longer on today.
      expect(find.byIcon(Icons.today), findsOneWidget);
    });

    testWidgets('"today" button jumps back to today', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      // Navigate forward first.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.today), findsOneWidget);

      await tester.tap(find.byIcon(Icons.today));
      await tester.pumpAndSettle();

      // Back on today → "today" button hidden again.
      expect(find.byIcon(Icons.today), findsNothing);
    });

    testWidgets('tapping a day card in weekly view opens that day',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      // Enter weekly view.
      await tester.tap(find.byIcon(Icons.calendar_view_week));
      await tester.pumpAndSettle();

      // Tap the first card (Monday of the current week).
      await tester.tap(find.byType(Card).first);
      await tester.pumpAndSettle();

      // Should be back in daily view.
      expect(find.byType(Checkbox), findsNWidgets(5));
      expect(find.byIcon(Icons.view_day), findsNothing); // toggle reset
    });
  });

  // ── Weekly Planner Dialog ─────────────────────────────────────────────────

  Widget buildDialogLauncher(List<List<TextEditingController>> ctrls) {
    const labels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final monday = DateTime(2026, 4, 27);
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showDialog(
              context: ctx,
              builder: (_) => WeeklyPlannerDialog(
                nextMonday: monday,
                weekdayLabels: labels,
                controllers: ctrls,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  group('WeeklyPlannerDialog — Save button validation', () {
    testWidgets('Save is disabled when task-2 fields are empty', (tester) async {
      final ctrls = List.generate(
          7, (_) => List.generate(4, (_) => TextEditingController()));
      await tester.pumpWidget(buildDialogLauncher(ctrls));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Speichern'));
      expect(btn.onPressed, isNull);

      for (final dc in ctrls) {
        for (final c in dc) c.dispose();
      }
    });

    testWidgets('Save enables when all 7 task-2 fields are filled',
        (tester) async {
      final ctrls = List.generate(
          7, (_) => List.generate(4, (_) => TextEditingController()));
      await tester.pumpWidget(buildDialogLauncher(ctrls));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final task2Fields = find.widgetWithText(TextField, 'Aufgabe 2  *');
      for (int i = 0; i < 7; i++) {
        await tester.enterText(task2Fields.at(i), 'Task $i');
      }
      await tester.pump();

      final btn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Speichern'));
      expect(btn.onPressed, isNotNull);

      for (final dc in ctrls) {
        for (final c in dc) c.dispose();
      }
    });
  });

  group('WeeklyPlannerDialog — optional tasks', () {
    testWidgets('optional fields are hidden by default', (tester) async {
      final ctrls = List.generate(
          7, (_) => List.generate(4, (_) => TextEditingController()));
      await tester.pumpWidget(buildDialogLauncher(ctrls));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Aufgabe 3  (optional)'),
          findsNothing);

      for (final dc in ctrls) {
        for (final c in dc) c.dispose();
      }
    });

    testWidgets('tapping + reveals optional fields for that day', (tester) async {
      final ctrls = List.generate(
          7, (_) => List.generate(4, (_) => TextEditingController()));
      await tester.pumpWidget(buildDialogLauncher(ctrls));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester
          .tap(find.text('Weitere Aufgaben hinzufügen (optional)').first);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Aufgabe 3  (optional)'),
          findsWidgets);

      for (final dc in ctrls) {
        for (final c in dc) c.dispose();
      }
    });

    testWidgets('days with pre-filled optional tasks are pre-expanded',
        (tester) async {
      final ctrls = List.generate(7, (day) {
        final dc = List.generate(4, (_) => TextEditingController());
        if (day == 2) dc[1].text = 'Vorhandener Task 3';
        return dc;
      });
      await tester.pumpWidget(buildDialogLauncher(ctrls));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Vorhandener Task 3'), findsOneWidget);

      for (final dc in ctrls) {
        for (final c in dc) c.dispose();
      }
    });
  });

  group('LeftScreen — stats page', () {
    testWidgets('renders Statistiken title', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeftScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Statistiken'), findsOneWidget);
    });

    testWidgets('shows streak section with zero values by default', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeftScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Streak'), findsOneWidget);
      expect(find.text('0'), findsWidgets); // current + best both 0
    });

    testWidgets('shows all 5 task stage rows', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeftScreen()));
      await tester.pumpAndSettle();
      for (int i = 1; i <= 5; i++) {
        expect(find.textContaining('Stufe $i'), findsOneWidget);
      }
    });

    testWidgets('reflects saved streak and task totals from prefs', (tester) async {
      SharedPreferences.setMockInitialValues({
        'stat_streak_current': 7,
        'stat_streak_best': 14,
        'stat_total_task1': 10,
        'stat_total_task2': 8,
        'stat_total_task3': 6,
        'stat_total_task4': 4,
        'stat_total_task5': 2,
      });
      await tester.pumpWidget(const MaterialApp(home: LeftScreen()));
      await tester.pumpAndSettle();
      expect(find.text('7'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('10×'), findsOneWidget);
      expect(find.text('2×'), findsOneWidget);
    });

    testWidgets('refresh button reloads stats', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeftScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      // No crash; page still shows title.
      expect(find.text('Statistiken'), findsOneWidget);
    });
  });

  group('RightScreen — rewards inventory', () {
    testWidgets('renders the Belohnungen title', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RightScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Belohnungen'), findsOneWidget);
    });

    testWidgets('shows all 6 reward labels', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RightScreen()));
      await tester.pumpAndSettle();
      for (final label in [
        'Gaming', 'YouTube', 'Kino-Abend', 'Kuchen', 'Überraschung', 'Skip'
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('all rewards start at x0', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RightScreen()));
      await tester.pumpAndSettle();
      expect(find.text('x0'), findsNWidgets(6));
    });

    testWidgets('tapping a reward at 0 shows empty-stock dialog', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RightScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gaming'));
      await tester.pumpAndSettle();
      expect(
        find.text('Du hast keine dieser Belohnungen mehr.\nVerdiene sie zuerst!'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await tester.pumpAndSettle();
    });
  });

  group('SwipeNavigator — page swiping', () {
    testWidgets('swiping left reveals RightScreen', (WidgetTester tester) async {
      await tester.pumpWidget(const TodoApp());
      await tester.pumpAndSettle();

      // Swipe left (drag from right to left) to reveal the right page.
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.byType(RightScreen), findsOneWidget);
    });

    testWidgets('swiping right reveals LeftScreen', (WidgetTester tester) async {
      await tester.pumpWidget(const TodoApp());
      await tester.pumpAndSettle();

      // Swipe right (drag from left to right) to reveal the left page.
      await tester.drag(find.byType(PageView), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(find.byType(LeftScreen), findsOneWidget);
    });
  });
}
