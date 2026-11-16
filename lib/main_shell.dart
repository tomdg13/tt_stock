import 'package:flutter/material.dart';
import 'api.dart';
import 'pages.dart';
import 'widgets.dart';
import 'withdraw_list.dart';
import 'stock_request.dart';
import 'request_status_page.dart';

/// Bottom bar for pushed pages. Opens each tab's page on top of the home menu.
class ShellBar extends StatefulWidget {
  const ShellBar({super.key});
  @override
  State<ShellBar> createState() => _ShellBarState();
}

class _ShellBarState extends State<ShellBar> {
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  /// pending requests waiting for MY branch to approve
  Future<void> _loadPending() async {
    try {
      final mine = Api.user?['branchId'];
      final rows = asList(await Api.get('/stock/requests'));
      var n = 0;
      for (final r in rows) {
        if (pick(r, ['status']) == 'pending') {
          if (mine == null || '${r['supBranchId']}' == '$mine') n++;
        }
      }
      if (mounted) setState(() => _pending = n);
    } catch (_) {}
  }

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
      case 3:
        nav.push(MaterialPageRoute(builder: (_) => const RequestStatusPage()));
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      onDestinationSelected: (i) => _go(context, i),
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.list_alt_outlined),
          selectedIcon: Icon(Icons.list_alt),
          label: 'ລາຍການຂໍ',
        ),
        const NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2),
          label: 'ເບີກອາໄຫຼ່',
        ),
        const NavigationDestination(
          icon: Icon(Icons.history_outlined),
          selectedIcon: Icon(Icons.history),
          label: 'ປະຫວັດ',
        ),
        NavigationDestination(
          icon: Badge(
              isLabelVisible: _pending > 0,
              label: Text('$_pending'),
              child: const Icon(Icons.fact_check_outlined)),
          selectedIcon: Badge(
              isLabelVisible: _pending > 0,
              label: Text('$_pending'),
              child: const Icon(Icons.fact_check)),
          label: 'ສະຖານະ',
        ),
      ],
    );
  }
}
