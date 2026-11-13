import 'package:flutter/material.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  // current tab, shared so any pushed page can switch tabs
  static final ValueNotifier<int> tab = ValueNotifier<int>(0);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // TODO: replace these with your real pages
  final List<Widget> _pages = const [
    Center(child: Text('ລາຍການຂໍອາໄຫຼ່')),
    Center(child: Text('ເບີກອາໄຫຼ່')),
    Center(child: Text('ປະຫວັດ')),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MainShell.tab,
      builder: (context, index, _) => Scaffold(
        body: IndexedStack(index: index, children: _pages),
        bottomNavigationBar: const ShellBar(),
      ),
    );
  }
}

/// Reusable bottom bar. Put it in any Scaffold of a pushed page.
class ShellBar extends StatelessWidget {
  const ShellBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MainShell.tab,
      builder: (context, index, _) => NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          MainShell.tab.value = i;
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'ລາຍການຂໍ',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'ເບີກອາໄຫຼ່',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'ປະຫວັດ',
          ),
        ],
      ),
    );
  }
}
