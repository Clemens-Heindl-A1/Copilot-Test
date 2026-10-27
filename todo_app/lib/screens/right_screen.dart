import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show cinemaOpenedNotifier;

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class _Reward {
  final String key;
  final String label;
  final IconData icon;
  int count;

  _Reward({
    required this.key,
    required this.label,
    required this.icon,
    this.count = 0,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

/// The screen reached by swiping left-to-right from Home.
class RightScreen extends StatefulWidget {
  const RightScreen({super.key});

  @override
  State<RightScreen> createState() => _RightScreenState();
}

class _RightScreenState extends State<RightScreen> with WidgetsBindingObserver {
  static const _ytChannel = MethodChannel('com.todoapp.todo_app/youtube');

  static final List<_Reward> _catalog = [
    _Reward(key: 'gaming',    label: 'Gaming',       icon: Icons.sports_esports),
    _Reward(key: 'youtube',   label: 'YouTube',      icon: Icons.smart_display),
    _Reward(key: 'cinema',    label: 'Film',         icon: Icons.movie_creation),
    _Reward(key: 'cake',      label: 'Süßigkeiten',  icon: Icons.cake),
    _Reward(key: 'mystery',   label: 'Joker',        icon: Icons.help_outline),
    _Reward(key: 'skip',      label: 'Skip',         icon: Icons.fast_forward),
  ];

  bool _loading = true;
  bool _accessibilityEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cinemaOpenedNotifier.addListener(_onCinemaOpened);
    _loadCounts();
    _checkAccessibility();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cinemaOpenedNotifier.removeListener(_onCinemaOpened);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadCounts();
      _checkAccessibility();
    }
  }

  /// Called by [cinemaOpenedNotifier] when Chrome incognito is intercepted.
  void _onCinemaOpened() {
    final data = cinemaOpenedNotifier.value;
    if (data == null) return;
    cinemaOpenedNotifier.value = null; // consume
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleCinemaAccessDialog();
    });
  }

  Future<void> _checkAccessibility() async {
    try {
      await _ytChannel.invokeMethod('requestNotificationPermission');
    } catch (_) {}
    try {
      final enabled =
          await _ytChannel.invokeMethod<bool>('hasAccessibilityPermission') ?? false;
      if (mounted) setState(() => _accessibilityEnabled = enabled);
    } on MissingPluginException {
      // Not on Android — ignore.
    } catch (_) {}
  }

  Future<void> _loadCounts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (final r in _catalog) {
        r.count = prefs.getInt('reward_${r.key}') ?? 0;
      }
      _loading = false;
    });
  }

  Future<void> _saveCount(_Reward reward) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reward_${reward.key}', reward.count);
  }

  Future<void> _onTap(_Reward reward) async {
    final joker = _catalog.firstWhere((r) => r.key == 'mystery');

    if (reward.count <= 0) {
      // ── Joker fallback: offer to substitute a joker for any empty reward ──
      if (reward.key != 'mystery' && joker.count > 0) {
        final useJoker = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            icon: Icon(reward.icon, size: 40, color: Colors.orange.shade400),
            title: Text(reward.label),
            content: Text(
              'Du hast keine ${reward.label}-Belohnungen mehr.\n\n'
              'Du hast noch ${joker.count} Joker.\n'
              'Möchtest du einen Joker stattdessen verwenden?',
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Joker verwenden'),
              ),
            ],
          ),
        );
        if (useJoker == true) {
          setState(() => joker.count--);
          await _saveCount(joker);
          if (reward.key == 'youtube') await _useYouTubeToken();
          if (reward.key == 'cinema') await _useCinemaToken();
        }
        return;
      }

      // ── No tokens, no joker fallback ──
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: Icon(reward.icon, size: 40, color: Colors.teal.shade300),
          title: Text(reward.label),
          content: const Text(
            'Du hast keine dieser Belohnungen mehr.\n'
            'Verdiene sie zuerst!',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // ── Normal confirm dialog ──
    final isYouTube = reward.key == 'youtube';
    final isCinema  = reward.key == 'cinema';
    final hasAction = isYouTube || isCinema;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(reward.icon, size: 40, color: Colors.teal.shade400),
        title: Text(reward.label),
        content: Text(
          'Möchtest du eine "${reward.label}"-Belohnung einlösen?\n'
          'Verbleibend: ${reward.count}',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(hasAction ? 'Einlösen & öffnen' : 'Einlösen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => reward.count--);
      await _saveCount(reward);
      if (isYouTube) await _useYouTubeToken();
      if (isCinema)  await _useCinemaToken();
    }
  }

  // ── YouTube helpers ───────────────────────────────────────────────────────

  /// Launches YouTube after a normal reward redemption.
  Future<void> _useYouTubeToken() async {
    try {
      await _ytChannel.invokeMethod('launchYouTube');
    } on MissingPluginException {
      // Not on Android — ignore.
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('YouTube konnte nicht geöffnet werden.')),
        );
      }
    }
  }

  // ── Cinema (Chrome incognito) helpers ─────────────────────────────────────

  /// Marks today as "cinema used" in prefs, then opens Chrome in incognito.
  Future<void> _useCinemaToken() async {
    final prefs = await SharedPreferences.getInstance();
    final now   = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await prefs.setString('cinema_processed_date', today);
    try {
      await _ytChannel.invokeMethod('launchChromeIncognito');
    } on MissingPluginException {
      // Not on Android — ignore.
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chrome Inkognito konnte nicht geöffnet werden.')),
        );
      }
    }
  }

  /// Shows the cinema-access dialog triggered by the Accessibility Service.
  Future<void> _handleCinemaAccessDialog() async {
    await _loadCounts();
    if (!mounted) return;

    final cinemaReward = _catalog.firstWhere((r) => r.key == 'cinema');
    final joker        = _catalog.firstWhere((r) => r.key == 'mystery');

    final hasCinema = cinemaReward.count > 0;
    final hasJoker  = joker.count > 0;

    if (!hasCinema && !hasJoker) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: Icon(Icons.movie_creation, size: 40, color: Colors.grey.shade400),
          title: const Text('Film gesperrt'),
          content: const Text(
            'Du hast keine Film-Tokens und keine Joker mehr.\n'
            'Verdiene Belohnungen, indem du deine Aufgaben erledigst!',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final useJoker   = !hasCinema;
    final tokenLabel = useJoker ? 'Joker' : 'Film-Token';
    final tokenCount = useJoker ? joker.count : cinemaReward.count;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.movie_creation, size: 40, color: Colors.indigo),
        title: const Text('Inkognito öffnen'),
        content: Text(
          'Du möchtest Chrome Inkognito öffnen.\n'
          'Einen $tokenLabel einlösen?\n'
          'Verbleibend: $tokenCount',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Einlösen & öffnen'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    if (useJoker) {
      setState(() => joker.count--);
      await _saveCount(joker);
    } else {
      setState(() => cinemaReward.count--);
      await _saveCount(cinemaReward);
    }
    await _useCinemaToken();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal.shade50,
      appBar: AppBar(
        title: const Text('Belohnungen'),
        centerTitle: true,
        backgroundColor: Colors.teal.shade200,
        elevation: 0,
        actions: const [],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!_accessibilityEnabled) _buildAccessibilityBanner(),
                Expanded(child: _buildGrid()),
              ],
            ),
    );
  }

  Future<void> _openAccessibilityWithGuide() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('App-Wächter aktivieren'),
        content: const Text(
          'Auf der nächsten Seite:\n\n'
          '1. Suche „ToDo App" in der Liste und tippe darauf.\n'
          '2. Tippe auf „ToDo App-Wächter".\n'
          '3. Aktiviere den Schalter und bestätige mit „Zulassen".\n\n'
          'Danach kehre zurück — der Banner verschwindet automatisch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Zu den Einstellungen'),
          ),
        ],
      ),
    );
    if (go == true) {
      try {
        await _ytChannel.invokeMethod('openAccessibilitySettings');
      } catch (_) {}
    }
  }

  Widget _buildAccessibilityBanner() {
    return Material(
      color: Colors.orange.shade100,
      child: InkWell(
        onTap: _openAccessibilityWithGuide,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.accessibility_new, color: Colors.orange.shade800, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'App-Wächter inaktiv — hier tippen, um ihn zu aktivieren.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.orange.shade700),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.95,
      ),
      itemCount: _catalog.length,
      itemBuilder: (_, i) => _OctRewardCard(
        reward: _catalog[i],
        onTap: () => _onTap(_catalog[i]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Octagon reward card
// ─────────────────────────────────────────────────────────────────────────────

class _OctRewardCard extends StatelessWidget {
  const _OctRewardCard({required this.reward, required this.onTap});

  final _Reward reward;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final empty = reward.count <= 0;
    final fillColor  = empty ? Colors.grey.shade300  : Colors.teal.shade400;
    final cardColor  = empty ? Colors.grey.shade50   : Colors.teal.shade50;
    final textColor  = empty ? Colors.grey.shade500  : Colors.teal.shade800;
    final badgeBg    = empty ? Colors.grey.shade200  : Colors.teal.shade100;
    final badgeBorder= empty ? Colors.grey.shade400  : Colors.teal.shade300;

    return Card(
      elevation: empty ? 1 : 4,
      shadowColor: empty ? Colors.transparent : Colors.teal.withOpacity(0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      color: cardColor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        splashColor: Colors.teal.withOpacity(0.15),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Octagon shape
              CustomPaint(
                size: const Size(72, 72),
                painter: _OctPainter(color: fillColor),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Center(
                    child: Icon(
                      reward.icon,
                      size: 30,
                      color: empty ? Colors.grey.shade400 : Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Label
              Text(
                reward.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              // Count badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: badgeBorder),
                ),
                child: Text(
                  'x${reward.count}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Octagon painter (8-sided with rounded corners)
// ─────────────────────────────────────────────────────────────────────────────

class _OctPainter extends CustomPainter {
  const _OctPainter({required this.color});
  final Color color;

  static const int _sides = 8;
  static const double _cornerRadius = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width * 0.46;

    // Flat-top octagon: first vertex at 22.5° so a flat edge sits at the top
    final vertices = List.generate(_sides, (i) {
      final angle = (i * 360 / _sides + 22.5) * math.pi / 180;
      return Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
    });

    Offset _norm(Offset v) {
      final d = v.distance;
      return d == 0 ? Offset.zero : Offset(v.dx / d, v.dy / d);
    }

    // For each edge, compute start/end points inset by _cornerRadius
    final starts = <Offset>[];
    final ends   = <Offset>[];
    for (int i = 0; i < _sides; i++) {
      final a   = vertices[i];
      final b   = vertices[(i + 1) % _sides];
      final dir = _norm(b - a);
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

    // Subtle shadow
    canvas.drawShadow(path, Colors.black38, 5, false);

    // Fill
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_OctPainter old) => old.color != color;
}
