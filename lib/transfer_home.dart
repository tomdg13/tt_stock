import 'package:flutter/material.dart';
import 'pages.dart' show TransferScreen;

class TransferHome extends StatefulWidget {
  const TransferHome({super.key});
  @override
  State<TransferHome> createState() => _TransferHomeState();
}

class _TransferHomeState extends State<TransferHome> {
  int _tab = 0;
  static const _titles = ['ລາຍການໃບໂອນ', 'ສ້າງໃບໂອນ', 'PDF', 'Upload'];

  Widget _soon(String t) => Center(child: Text('$t · ກຳລັງພັດທະນາ'));

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const TransferScreen(key: ValueKey('trf-list'), showForm: false),
      TransferScreen(
          key: const ValueKey('trf-create'),
          showList: false,
          onCreated: () => setState(() => _tab = 0)),
      _soon('PDF'),
      _soon('Upload'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_tab])),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.list_alt_outlined), label: 'ລາຍການ'),
          NavigationDestination(
              icon: Icon(Icons.add_box_outlined), label: 'ສ້າງໃບໂອນ'),
          NavigationDestination(
              icon: Icon(Icons.picture_as_pdf_outlined), label: 'PDF'),
          NavigationDestination(
              icon: Icon(Icons.upload_file_outlined), label: 'Upload'),
        ],
      ),
    );
  }
}
