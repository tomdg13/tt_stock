import 'package:flutter/material.dart';
import 'pages.dart';
import 'withdraw_list.dart';
import 'stock_request.dart';

/// Bottom bar for pushed pages. Opens each tab's page on top of the home menu.
class ShellBar extends StatelessWidget {
  const ShellBar({super.key});

  void _go(BuildContext context, int i) {
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    switch (i) {
      case 0:
        nav.push(MaterialPageRoute(builder: (_) => const StockRequestsPage()));
        break;
      case 1:
        nav.push(MaterialPageRoute(builder: (_) => const WithdrawListPage()));
        break;
      case 2:
        nav.push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
        break;
      default:
        break; // tab 2: back to home menu for now
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      onDestinationSelected: (i) => _go(context, i),
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
    );
  }
}
