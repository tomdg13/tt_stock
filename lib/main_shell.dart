import 'package:flutter/material.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  // TODO: replace these with your real pages
  final List<Widget> _pages = const [
    Center(child: Text('ລາຍການຂໍອາໄຫຼ່')),
    Center(child: Text('ເບີກອາໄຫຼ່')),
    Center(child: Text('ປະຫວັດ')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
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
