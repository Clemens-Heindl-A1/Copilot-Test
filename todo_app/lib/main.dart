import 'package:flutter/material.dart';
import 'debug_seed.dart';
import 'screens/home_screen.dart';
import 'screens/left_screen.dart';
import 'screens/right_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Seed realistic test data in debug builds (one-time, idempotent).
  assert(() { seedDebugData(); return true; }());
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

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pageController,
      physics: const BouncingScrollPhysics(),
      children: const [
        LeftScreen(),
        HomeScreen(),
        RightScreen(),
      ],
    );
  }
}
