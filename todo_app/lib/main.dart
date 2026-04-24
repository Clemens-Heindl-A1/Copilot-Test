import 'package:flutter/material.dart';
import 'debug_seed.dart';
import 'screens/home_screen.dart';
import 'screens/left_screen.dart';
import 'screens/right_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Seed realistic test data in debug builds (one-time, idempotent).
  var isDebug = false;
  assert(() {
    isDebug = true;
    return true;
  }());
  if (isDebug) {
    await seedDebugData();
  }
  runApp(const TodoApp());
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Todo App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SwipeNavigator(),
    );
  }
}

/// Root widget that hosts the three-page swipe navigation.
/// Pages order: [LeftScreen] | [HomeScreen] | [RightScreen]
/// The app starts on [HomeScreen] (index 1).
class SwipeNavigator extends StatefulWidget {
  const SwipeNavigator({super.key});

  @override
  State<SwipeNavigator> createState() => _SwipeNavigatorState();
}

class _SwipeNavigatorState extends State<SwipeNavigator> {
  static const int _initialPage = 1;

  late final PageController _pageController;
  int _currentPage = _initialPage;

  // Pages order: Stats | Tasks | Rewards

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _initialPage);
    _pageController.addListener(_onPageChanged);
  }

  void _onPageChanged() {
    final page = _pageController.page?.round() ?? _initialPage;
    if (page != _currentPage) {
      setState(() => _currentPage = page);
    }
  }

  void _onNavTap(int index) {
    if (index == _currentPage) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  static const _labels = ['Statistiken', 'Aufgaben', 'Belohnungen'];
  static const _iconsOutlined = [
    Icons.bar_chart_outlined,
    Icons.checklist_outlined,
    Icons.card_giftcard_outlined,
  ];
  static const _iconsFilled = [
    Icons.bar_chart,
    Icons.checklist,
    Icons.card_giftcard,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: PageView(
        controller: _pageController,
        physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
        children: const [
          LeftScreen(),
          HomeScreen(),
          RightScreen(),
        ],
      ),
      bottomNavigationBar: _buildFloatingNavBar(),
    );
  }

  Widget _buildFloatingNavBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(36),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurple.withOpacity(0.20),
                blurRadius: 24,
                spreadRadius: 0,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.deepPurple.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
              const BoxShadow(
                color: Colors.white,
                blurRadius: 0,
                spreadRadius: 1,
                offset: Offset(0, -1),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(3, _buildNavItem),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index) {
    final active = index == _currentPage;
    return GestureDetector(
      onTap: () => _onNavTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.deepPurple.shade600 : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.40),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? _iconsFilled[index] : _iconsOutlined[index],
              color: active ? Colors.white : Colors.grey.shade500,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              _labels[index],
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
