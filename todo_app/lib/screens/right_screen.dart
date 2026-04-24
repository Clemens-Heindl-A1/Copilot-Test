import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _RightScreenState extends State<RightScreen> {
  static final List<_Reward> _catalog = [
    _Reward(key: 'gaming',    label: 'Gaming',       icon: Icons.sports_esports),
    _Reward(key: 'youtube',   label: 'YouTube',      icon: Icons.smart_display),
    _Reward(key: 'cinema',    label: 'Kino-Abend',   icon: Icons.movie_creation),
    _Reward(key: 'cake',      label: 'Kuchen',       icon: Icons.cake),
    _Reward(key: 'mystery',   label: 'Überraschung', icon: Icons.help_outline),
    _Reward(key: 'skip',      label: 'Skip',         icon: Icons.fast_forward),
  ];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCounts();
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
    // Already at minimum — warn the user.
    if (reward.count <= 0) {
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

    // Confirm use.
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
            child: const Text('Einlösen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => reward.count--);
      await _saveCount(reward);
    }
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildGrid(),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: 0.9,
      ),
      itemCount: _catalog.length,
      itemBuilder: (_, i) => _HexRewardCard(
        reward: _catalog[i],
        onTap: () => _onTap(_catalog[i]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hexagon reward card
// ─────────────────────────────────────────────────────────────────────────────

class _HexRewardCard extends StatelessWidget {
  const _HexRewardCard({required this.reward, required this.onTap});

  final _Reward reward;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final empty = reward.count <= 0;
    final color = empty ? Colors.grey.shade300 : Colors.teal.shade400;
    final textColor = empty ? Colors.grey.shade500 : Colors.teal.shade800;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Hexagon
          CustomPaint(
            size: const Size(96, 96),
            painter: _HexPainter(color: color),
            child: SizedBox(
              width: 96,
              height: 96,
              child: Center(
                child: Icon(
                  reward.icon,
                  size: 38,
                  color: empty ? Colors.grey.shade400 : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Label
          Text(
            reward.label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          // Count badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: empty
                  ? Colors.grey.shade200
                  : Colors.teal.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: empty
                    ? Colors.grey.shade400
                    : Colors.teal.shade300,
              ),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hexagon painter
// ─────────────────────────────────────────────────────────────────────────────

class _HexPainter extends CustomPainter {
  const _HexPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width / 2;

    final path = Path();
    for (int i = 0; i < 6; i++) {
      // Pointy-top hexagon
      final angle = (i * 60 - 30) * (math.pi / 180);
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    // Shadow
    canvas.drawShadow(path, Colors.black26, 4, false);

    // Fill
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.color != color;
}
