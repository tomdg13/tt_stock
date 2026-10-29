import 'package:mobile_scanner/mobile_scanner.dart';
import 'stock_drill.dart';
import 'purchase_plan_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'crud.dart';
import 'lao.dart';
import 'pages.dart';
import 'specs.dart';
import 'terminal_actions.dart';
import 'forecast.dart';
import 'atm_info.dart';
import 'atm_ocr.dart';
import 'terminal_model_filter.dart';
import 'terminal_pick_list.dart';
import 'terminal_history.dart';
import 'type_image.dart';
import 'theme.dart';
import 'widgets.dart';
import 'transfer_report.dart';
import 'stock_count.dart';

// ---------------------------------------------------------------- Login
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_phone.text.trim().isEmpty || _pin.text.isEmpty) {
      setState(() {
        _error = 'ໃສ່ເບີໂທ ແລະ PIN';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.login(_phone.text.trim(), _pin.text);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = '$e';
        });
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('TT Stock',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Server',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: AppCard(
              title: 'ເຂົ້າສູ່ລະບົບ',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'ເບີໂທ', hintText: '20 5555 0001'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 6,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                          labelText: 'PIN', hintText: '••••', counterText: ''),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_error!,
                            style: TextStyle(color: p.bad),
                            textAlign: TextAlign.center),
                      ),
                    const SizedBox(height: 16),
                    saveButton('ເຂົ້າສູ່ລະບົບ', _busy, _submit),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- Home
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late String _key = _firstKey();

  bool _allowed(MenuItemDef m) => m.need.isEmpty || m.need.any(Api.can);

  String _firstKey() {
    final pref = Api.user?['role'] == 'warehouse' ? 'stock' : 'dash';
    for (final g in menuGroups) {
      for (final i in g.items) {
        if (i.key == pref && _allowed(i)) return pref;
      }
    }
    for (final g in menuGroups) {
      for (final i in g.items) {
        if (_allowed(i)) return i.key;
      }
    }
    return 'dash';
  }

  Widget _page(String k) {
    final sp = crudSpec(k);
    if (sp != null) return CrudPage(sp);
    switch (k) {
      case 'dash':
        return const DashMenuScreen();
      case 'stock':
        return const StockScreen();
      case 'recv':
        return const StockFormPage(issue: false);
      case 'issue':
        return ListPage(
          title: 'ຕູ້ ATM',
          path: '/atms',
          extraQuery: 'limit=100',
          titleKeys: const ['atmId'],
          subKeys: const ['atmLocation', 'location', 'groupName', 'atmGroupId'],
          tagKeys: const ['atmStatus', 'status'],
          rowFilter: (m) =>
              pick(m, ['atmStatus', 'status']).toLowerCase() == 'active',
          onTapItem: (ctx, m) => Navigator.push(
            ctx,
            MaterialPageRoute(builder: (_) => AtmIssueHub(pick(m, ['atmId']))),
          ),
        );
      case 'trf':
        return const TransferScreen();
      case 'hist':
        return const HistoryScreen();
      case 'ser':
        return const SearchPage();
      case 'bins':
        return const ListPage(
            title: 'ບ່ອນເກັບ',
            path: '/bins',
            titleKeys: ['code', 'name'],
            subKeys: ['name', 'description'],
            searchable: false);
      case 'plans':
        return ListPage(
          title: 'ແຜນຈັດຊື້',
          path: '/plans',
          searchable: false,
          titleKeys: const ['planNo', 'name', 'id'],
          subKeys: const ['vendorName', 'brandName'],
          tagKeys: const ['status'],
          detailPath: (m) => '/plans/${pick(m, ['id'])}',
        );
      case 'vendors':
        return const ListPage(
            title: 'Vendor',
            path: '/vendors',
            titleKeys: ['name'],
            subKeys: ['phone', 'contact'],
            searchable: false);
      case 'prod':
        return ListPage(
          title: 'ສິນຄ້າ',
          path: '/products',
          extraQuery: 'limit=100',
          titleKeys: const ['name', 'productName'],
          subKeys: const ['typeName', 'brandName', 'code'],
          trailKeys: const ['stock', 'qty'],
          detailPath: (m) => '/products/${pick(m, ['id', 'productId'])}',
        );
      case 'brand':
        return const ListPage(
            title: 'BRAND',
            path: '/brands',
            titleKeys: ['name'],
            searchable: false);
      case 'model':
        return const ListPage(
            title: 'MODEL',
            path: '/models',
            titleKeys: ['name'],
            subKeys: ['brandName', 'legacyName'],
            searchable: false);
      case 'atms':
        return ListPage(
          title: 'ຕູ້ ATM',
          path: '/atms',
          extraQuery: 'limit=100',
          titleKeys: const ['atmId'],
          subKeys: const ['atmLocation', 'location', 'groupName', 'atmGroupId'],
          tagKeys: const ['atmStatus', 'status'],
          detailPath: (m) => '/atms/${Uri.encodeComponent(pick(m, ['atmId']))}',
          rowFilter: (m) =>
              pick(m, ['atmStatus', 'status']).toLowerCase() == 'active',
        );
      case 'terms':
        return ListPage(
          title: 'Terminal',
          path: '/terminals',
          extraQuery: 'limit=100',
          titleKeys: const ['barcode'],
          subKeys: const ['typeName', 'atmId'],
          tagKeys: const ['state', 'status'],
          detailPath: (m) =>
              '/terminals/${Uri.encodeComponent(pick(m, ['barcode']))}',
        );
      case 'actrep':
        return const ListPage(
          title: 'Activity Report',
          path: '/activity-report',
          titleKeys: ['barcode'],
          subKeys: ['atmId', 'user', 'createdAt'],
          tagKeys: ['status'],
        );
      case 'ttypes':
        return const ListPage(
            title: 'ປະເພດ Terminal',
            path: '/terminal-types',
            titleKeys: ['name', 'code'],
            subKeys: ['code', 'id'],
            searchable: false);
      case 'users':
        return const ListPage(
          title: 'ຜູ້ໃຊ້',
          path: '/users',
          searchable: false,
          titleKeys: ['fullName', 'name', 'phone'],
          subKeys: ['phone', 'branchName'],
          tagKeys: ['roleName', 'role'],
        );
      case 'roles':
        return const ListPage(
            title: 'ບົດບາດ',
            path: '/roles',
            searchable: false,
            titleKeys: ['name', 'roleName'],
            subKeys: ['scope']);
      case 'funcs':
        return const ListPage(
            title: 'ຟັງຊັນ',
            path: '/functions',
            searchable: false,
            titleKeys: ['name', 'id'],
            subKeys: ['id']);
      case 'branches':
        return const ListPage(
            title: 'ສາຂາ',
            path: '/branches',
            searchable: false,
            titleKeys: ['name'],
            subKeys: ['code']);
    }
    return const SizedBox();
  }

  Widget _tile(MenuItemDef m) {
    final p = pal(context);
    final sel = m.key == _key;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: sel ? p.pri : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: Icon(m.icon, size: 20, color: sel ? p.prit : p.tx),
          title: Text(m.label,
              style: TextStyle(
                  color: sel ? p.prit : p.tx,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
          onTap: () {
            setState(() {
              _key = m.key;
            });
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  Widget _drawer() {
    final p = pal(context);
    final u = Api.user ?? {};
    final role = pick(u, ['role']);
    final hasBranch = pick(u, ['branchId']).isNotEmpty;
    return Drawer(
      child: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration:
                BoxDecoration(border: Border(bottom: BorderSide(color: p.bd))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TT Stock',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(pick(u, ['name', 'fullName', 'phone']),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, children: [
                if (role.isNotEmpty) Tag(roleNames[role] ?? role),
                Tag(hasBranch ? 'ສາຂາຕົນເອງ' : 'ທຸກສາຂາ',
                    hasBranch ? '' : 'in'),
              ]),
            ]),
          ),
          Expanded(
            child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final g in menuGroups) ..._group(g),
                ]),
          ),
          Divider(height: 1, color: p.bd),
          ListTile(
            dense: true,
            leading: const Icon(Icons.settings_outlined),
            title: const Text('ຕັ້ງຄ່າ Server'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
          ListTile(
            dense: true,
            leading: Icon(Icons.logout, color: p.bad),
            title: Text('ອອກຈາກລະບົບ', style: TextStyle(color: p.bad)),
            onTap: () => Api.logout(),
          ),
        ]),
      ),
    );
  }

  List<Widget> _group(MenuGroup g) {
    final p = pal(context);
    final items = g.items.where(_allowed).toList();
    if (items.isEmpty) return [];
    if (g.title == null) return [for (final i in items) _tile(i)];
    return [
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 18),
          childrenPadding: EdgeInsets.zero,
          title: Text(g.title!,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: p.mut)),
          children: [for (final i in items) _tile(i)],
        ),
      ),
    ];
  }

  Widget? _bottomBar() {
    const keys = ['dash', 'stock', 'recv', 'issue'];
    final tabs = <MenuItemDef>[
      for (final g in menuGroups)
        for (final i in g.items)
          if (keys.contains(i.key) && _allowed(i)) i,
    ];
    if (tabs.isEmpty) return null;
    final idx = tabs.indexWhere((t) => t.key == _key);
    return Builder(
      builder: (ctx) => NavigationBar(
        selectedIndex: idx >= 0 ? idx : tabs.length,
        onDestinationSelected: (i) {
          if (i < tabs.length) {
            setState(() => _key = tabs[i].key);
          } else {
            Scaffold.of(ctx).openDrawer();
          }
        },
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
          const NavigationDestination(
              icon: Icon(Icons.menu), label: 'ເພີ່ມເຕີມ'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(labelOf(_key),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_key != 'dash' && Api.can('STOCK_VIEW'))
            IconButton(
              icon: const Icon(Icons.photo_camera_outlined),
              tooltip: 'ຖ່າຍຮູບເລກຕູ້ ATM',
              onPressed: () => openAtmFromPhoto(context),
            ),
          if (_key != 'dash' && Api.can('STOCK_VIEW'))
            IconButton(
              icon: const Icon(Icons.trending_up),
              tooltip: 'ຄາດການຊື້ອາໄຫຼ່',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ForecastPage())),
            ),
          if (_key != 'dash' && Api.can('STOCK_VIEW'))
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'ຄົ້ນຫາ',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SearchScreen())),
            ),
        ],
      ),
      drawer: _drawer(),
      bottomNavigationBar: _bottomBar(),
      body: KeyedSubtree(key: ValueKey(_key), child: _page(_key)),
    );
  }
}

// ------------------------------------------------------------ Dashboard
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<dynamic> _f = Api.get('/dashboard');
  void _reload() => setState(() {
        _f = Api.get('/dashboard');
      });

  bool _warn(String k) {
    final s = k.toLowerCase();
    return s.contains('low') || s.contains('pending') || s.contains('transit');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _f,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) return ErrorView(s.error!, _reload);
        dynamic d = s.data;
        if (d is Map && d.length == 1 && d['data'] is Map) d = d['data'];
        if (d is! Map) {
          return ListView(
              padding: const EdgeInsets.all(16),
              children: [AppCard(child: DataView(d))]);
        }
        final kpis = <Widget>[];
        final cards = <Widget>[];
        d.forEach((k, v) {
          final key = k.toString(), label = prettyKey(key);
          if (v is num || (v is String && num.tryParse(v) != null)) {
            kpis.add(Kpi('$v', label));
          } else if (v is List) {
            kpis.add(
                Kpi('${v.length}', label, warn: v.isNotEmpty && _warn(key)));
            cards.add(AppCard(title: label, child: _rows(context, v)));
          } else if (v is Map) {
            cards.add(AppCard(
              title: label,
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in v.entries)
                  InfoChip(prettyKey('${e.key}'), '${e.value}'),
              ]),
            ));
          }
        });
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            LayoutBuilder(
              builder: (_, bc) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final k in kpis)
                    SizedBox(width: (bc.maxWidth - 12) / 2, child: k)
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...cards,
          ]),
        );
      },
    );
  }

  Widget _rows(BuildContext context, List v) {
    final p = pal(context);
    if (v.isEmpty) return Text('ບໍ່ມີລາຍການ', style: TextStyle(color: p.mut));
    return Column(children: [
      for (final x in v.take(10))
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: p.bd))),
          child: _row(context, x),
        ),
    ]);
  }

  Widget _row(BuildContext context, dynamic x) {
    final p = pal(context);
    if (x is! Map) return Text('$x');
    final vals = x.entries
        .where((e) => e.value != null && e.value is! Map && e.value is! List)
        .toList();
    if (vals.isEmpty) return const SizedBox();
    final rest = vals
        .skip(1)
        .take(3)
        .map((e) => '${prettyKey('${e.key}')}: ${e.value}')
        .join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${vals.first.value}',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      if (rest.isNotEmpty)
        Text(rest, style: TextStyle(color: p.mut, fontSize: 12)),
    ]);
  }
}

// --------------------------------------------------------------- Search
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('ຄົ້ນຫາ')), body: const SearchPage());
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _q = TextEditingController();
  Future<dynamic>? _f;
  bool _busy = false;

  Future<dynamic> _tryGet(String path) async {
    try {
      return await Api.get(path);
    } catch (_) {
      return null;
    }
  }

  /// Works out what was typed / scanned: terminal barcode, product barcode, ATM id, else serial search.
  Future<void> _go([String? text]) async {
    final q = (text ?? _q.text).trim();
    if (q.isEmpty || _busy) return;
    _q.text = q;
    setState(() {
      _busy = true;
      _f = null;
    });
    final enc = Uri.encodeComponent(q);
    try {
      final t = await _tryGet('/terminals/$enc');
      if (t is Map) {
        final bc = pick(Map<String, dynamic>.from(t), ['barcode']);
        if (bc.isNotEmpty && mounted) {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TerminalInfoPage({'barcode': bc})));
          return;
        }
      }
      final pr = await _tryGet('/products/by-barcode/$enc');
      if (pr is Map && pr['productId'] != null) {
        final sp = crudSpec('prod');
        if (sp != null && mounted) {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CrudDetail(
                      sp, {'id': pr['productId'], 'name': pr['name']},
                      onChanged: () {})));
          return;
        }
      }
      final a = await _tryGet('/atms/$enc');
      if (a is Map) {
        final id = pick(Map<String, dynamic>.from(a), ['atmId']);
        if (id.isNotEmpty && mounted) {
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => AtmIssueHub(id)));
          return;
        }
      }
      if (mounted) {
        setState(() {
          _f = Api.get('/search?q=${Uri.encodeQueryComponent(q)}');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _scan() async {
    final s = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const BarcodeScanPage()));
    if (s != null && s.trim().isNotEmpty) _go(s);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _go(),
          decoration: InputDecoration(
            hintText: 'ATM ID / Barcode / Serial',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'ສະແກນ',
                  onPressed: _scan),
              IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _go()),
            ]),
          ),
        ),
      ),
      Expanded(
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : _f == null
                ? Center(
                    child: Text(
                        'ພິມ ຫຼື ສະແກນ: ID ຕູ້ ATM · Barcode Terminal · Barcode ສິນຄ້າ · Serial',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.mut)))
                : FutureBuilder(
                    future: _f,
                    builder: (c, s) {
                      if (s.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (s.hasError) return ErrorView(s.error!, () => _go());
                      return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: [AppCard(child: DataView(s.data))]);
                    }),
      ),
    ]);
  }
}

// ------------------------------------------------------------- Settings
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _url = TextEditingController(text: Api.baseUrl);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ຕັ້ງຄ່າ Server')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Server URL (ລົງທ້າຍດ້ວຍ /api)'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton(
                  onPressed: () => _url.text = defaultBaseUrl,
                  child: const Text('ຣີເຊັດ')),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () async {
                  await Api.saveBaseUrl(_url.text);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ບັນທຶກແລ້ວ')));
                  Navigator.pop(context);
                },
                child: const Text('ບັນທຶກ'),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------ ATM hub for Issue
class AtmIssueHub extends StatefulWidget {
  final String atmId;
  const AtmIssueHub(this.atmId, {super.key});
  @override
  State<AtmIssueHub> createState() => _AtmIssueHubState();
}

class _AtmIssueHubState extends State<AtmIssueHub> {
  int _rev = 0;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<bool> _confirm(String msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ຢືນຢັນ'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('ບັນທຶກ')),
        ],
      ),
    );
    return ok == true;
  }

  Future<String?> _scan() => Navigator.push<String>(
      context, MaterialPageRoute(builder: (_) => const BarcodeScanPage()));

  // searchable list of terminals that are not In Use, with add / edit / delete
  Future<Map<String, dynamic>?> _pickTerminal({String? typeId}) {
    final extra = typeId == null
        ? 'limit=500'
        : 'limit=500&typeId=${Uri.encodeQueryComponent(typeId)}';
    final spec = crudSpec('terms');
    final canEdit = spec != null && spec.canWrite;
    final sig = ValueNotifier<int>(0);
    return Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (pc) => Scaffold(
          appBar: AppBar(
            title: const Text('ເລືອກ Terminal'),
            actions: [
              if (canEdit)
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('ເພີ່ມ'),
                  onPressed: () async {
                    final ok = await Navigator.push<bool>(
                        pc, MaterialPageRoute(builder: (_) => CrudForm(spec!)));
                    if (ok == true) sig.value++;
                  },
                ),
            ],
          ),
          body: ModelFilterBody(
            atmId: widget.atmId,
            builder: (mf) => TerminalPickList(
              extraQuery: extra,
              rowFilter: (m) => '${m['state'] ?? ''}' != 'In Use' && mf(m),
              onTap: (m) => Navigator.pop(pc, m),
              reloadSignal: sig,
              onEdit: canEdit
                  ? (m) async {
                      final ok = await Navigator.push<bool>(
                          pc,
                          MaterialPageRoute(
                              builder: (_) => CrudForm(spec!, row: m)));
                      if (ok == true) sig.value++;
                    }
                  : null,
              onDelete: canEdit
                  ? (m) async {
                      if (await confirmDelete(pc, spec!, m)) sig.value++;
                    }
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  // terminals currently In Use in this ATM
  Future<Map<String, dynamic>?> _pickCurrent() async {
    final d = await Api.get('/atms/${Uri.encodeComponent(widget.atmId)}');
    final terms = d is Map && d['terminals'] is List
        ? asList(d['terminals'])
        : <Map<String, dynamic>>[];
    if (!mounted) return null;
    if (terms.isEmpty) {
      _snack('ບໍ່ມີ Terminal ໃນຕູ້ນີ້ ໃຫ້ໃຊ້ "ເພີ່ມ" ກ່ອນ');
      return null;
    }
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('ເລືອກ Terminal ທີ່ຈະປ່ຽນອອກ',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          for (final t in terms)
            ListTile(
              leading: const Icon(Icons.memory),
              title: Text(pick(t, ['barcode'])),
              subtitle: Text([
                pick(t, ['typeName']),
                pick(t, ['serial'])
              ].where((e) => e.isNotEmpty).join(' · ')),
              onTap: () => Navigator.pop(c, t),
            ),
        ]),
      ),
    );
  }

  Future<void> _addCode(String? code) async {
    if (code == null || code.trim().isEmpty || !mounted) return;
    final barcode = code.trim();
    try {
      final info = await Api.get('/terminals/${Uri.encodeComponent(barcode)}');
      if (!mounted) return;
      final st = info is Map ? '${info['state'] ?? ''}' : '';
      final cur = info is Map ? '${info['atmId'] ?? ''}' : '';
      if (st == 'In Use' && cur == widget.atmId) {
        _snack('Terminal ນີ້ຢູ່ໃນຕູ້ນີ້ແລ້ວ');
        return;
      }
      final msg = st == 'In Use' && cur.isNotEmpty
          ? 'Terminal $barcode ຢູ່ໃນຕູ້ $cur ແລ້ວ. ຍ້າຍມາຕູ້ ${widget.atmId}?'
          : 'ເພີ່ມ Terminal $barcode ເຂົ້າຕູ້ ${widget.atmId}?';
      if (!await _confirm(msg)) return;
      await Api.post('/activities',
          {'status': 'In Use', 'barcode': barcode, 'atmId': widget.atmId});
      if (!mounted) return;
      setState(() {
        _rev++;
      });
      _snack('ບັນທຶກແລ້ວ');
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _addScan() async => _addCode(await _scan());

  Future<void> _addPick() async {
    final m = await _pickTerminal();
    if (m != null) await _addCode(pick(m, ['barcode']));
  }

  Future<void> _replace(bool byScan) async {
    try {
      final old = await _pickCurrent();
      if (old == null || !mounted) return;
      final oldCode = pick(old, ['barcode']);
      final oi = await Api.get('/terminals/${Uri.encodeComponent(oldCode)}');
      final typeId =
          oi is Map && oi['typeId'] != null ? '${oi['typeId']}' : null;
      if (!mounted) return;
      String? raw;
      if (byScan) {
        raw = await _scan();
      } else {
        final m = await _pickTerminal(typeId: typeId);
        raw = m == null ? null : pick(m, ['barcode']);
      }
      if (raw == null || raw.trim().isEmpty || !mounted) return;
      final nc = raw.trim();
      if (nc == oldCode) {
        _snack('Terminal ຊ້ຳກັນ');
        return;
      }
      final ni = await Api.get('/terminals/${Uri.encodeComponent(nc)}');
      if (!mounted) return;
      final st = ni is Map ? '${ni['state'] ?? ''}' : '';
      final cur = ni is Map ? '${ni['atmId'] ?? ''}' : '';
      if (st == 'In Use' && cur == widget.atmId) {
        _snack('Terminal ໃໝ່ຢູ່ໃນຕູ້ນີ້ແລ້ວ');
        return;
      }
      final warn = <String>[
        if (st == 'In Use' && cur.isNotEmpty) 'Terminal ໃໝ່ຢູ່ໃນຕູ້ $cur',
        if (typeId != null && ni is Map && '${ni['typeId']}' != typeId)
          'ປະເພດບໍ່ຕົງກັນ',
      ];
      final note = warn.isEmpty ? '' : '\n⚠ ' + warn.join(', ');
      if (!await _confirm('ປ່ຽນ $oldCode → $nc ໃນຕູ້ ${widget.atmId}?$note'))
        return;
      await Api.post('/atms/${Uri.encodeComponent(widget.atmId)}/replace',
          {'oldBarcode': oldCode, 'newBarcode': nc});
      if (!mounted) return;
      setState(() {
        _rev++;
      });
      _snack('ປ່ຽນແລ້ວ');
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Widget _act(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final atmId = widget.atmId;
    final canAdd = Api.can('ATM_MANAGE');
    return Scaffold(
      appBar: AppBar(title: Text('ຕູ້ ATM · $atmId')),
      body: AtmTerminalTree(atmId,
          key: ValueKey(_rev), onAdd: canAdd ? _addScan : null),
      bottomNavigationBar: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              if (canAdd) ...[
                _act(Icons.playlist_add, 'ເພີ່ມ · ເລືອກ', _addPick),
                _act(Icons.qr_code_scanner, 'ເພີ່ມ · ສະແກນ', _addScan),
              ],
              _act(
                  Icons.history,
                  'ປະຫວັດ',
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => HistoryPage(atmId: atmId)))),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ barcode scanner
class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key});
  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage> {
  bool _done = false;

  void _finish(String v) {
    if (_done) return;
    _done = true;
    Navigator.pop(context, v);
  }

  Future<void> _manual() async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ປ້ອນ Barcode'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Barcode'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(d, c.text),
              child: const Text('ຕົກລົງ')),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty) _finish(v.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ສະແກນ Barcode'),
        actions: [
          IconButton(
              icon: const Icon(Icons.keyboard_outlined),
              tooltip: 'ປ້ອນເອງ',
              onPressed: _manual),
        ],
      ),
      body: MobileScanner(
        onDetect: (capture) {
          for (final b in capture.barcodes) {
            final v = b.rawValue;
            if (v != null && v.isNotEmpty) {
              _finish(v);
              break;
            }
          }
        },
      ),
    );
  }
}

// ------------------------------------------------------------ ATM -> terminals -> products
class AtmTerminalTree extends StatefulWidget {
  final String atmId;
  final VoidCallback? onAdd;
  const AtmTerminalTree(this.atmId, {super.key, this.onAdd});
  @override
  State<AtmTerminalTree> createState() => _AtmTerminalTreeState();
}

class _AtmTerminalTreeState extends State<AtmTerminalTree> {
  late Future<dynamic> _f = _load();

  Future<dynamic> _load() =>
      Api.get('/atms/${Uri.encodeComponent(widget.atmId)}');
  void _reload() => setState(() {
        _f = _load();
      });

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return FutureBuilder(
      future: _f,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) return ErrorView(s.error!, _reload);
        final d = s.data;
        final terms = d is Map && d['terminals'] is List
            ? asList(d['terminals'])
            : <Map<String, dynamic>>[];
        final info =
            d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: terms.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                      AtmInfoCard(info),
                      const SizedBox(height: 80),
                      Center(
                          child: Text('ຍັງບໍ່ມີ Terminal ໃນຕູ້ນີ້',
                              style: TextStyle(color: p.mut))),
                      if (widget.onAdd != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Center(
                            child: FilledButton.tonalIcon(
                              onPressed: widget.onAdd,
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('ເພີ່ມ Terminal'),
                            ),
                          ),
                        ),
                    ])
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    AtmInfoCard(info),
                    const SizedBox(height: 8),
                    for (final t in terms)
                      _TerminalTile(t, atmId: widget.atmId, onChanged: _reload)
                  ],
                ),
        );
      },
    );
  }
}

class _TerminalTile extends StatelessWidget {
  final Map<String, dynamic> t;
  final String atmId;
  final VoidCallback onChanged;
  const _TerminalTile(this.t, {required this.atmId, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final barcode = pick(t, ['barcode']);
    final sub = [
      pick(t, ['typeName']),
      pick(t, ['model']),
      pick(t, ['serial'])
    ].where((e) => e.isNotEmpty).join(' · ');
    return cardBox(
      context,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: typeThumb(context, pick(t, ['typeImage', 'imageFile'])),
        title:
            Text(barcode, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: sub.isEmpty
            ? null
            : Text(sub, style: TextStyle(color: p.mut, fontSize: 13)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openTerminalInfo(
          context,
          {'atmId': atmId, 'state': kInUse, ...t},
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ Dashboard menu grid
class _DashMenuItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _DashMenuItem(this.icon, this.label, this.color, this.onTap);
}

class DashMenuScreen extends StatelessWidget {
  const DashMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <_DashMenuItem>[
      if (Api.can('STOCK_VIEW'))
        _DashMenuItem(Icons.photo_camera_outlined, 'ຖ່າຍຮູບເລກຕູ້ ATM',
            Colors.blue, () => openAtmFromPhoto(context)),
      if (Api.can('STOCK_VIEW'))
        _DashMenuItem(
            Icons.trending_up,
            'ຄາດການຊື້ອາໄຫຼ່',
            Colors.teal,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ForecastPage()))),
      if (Api.can('STOCK_VIEW'))
        _DashMenuItem(
            Icons.search,
            'ຄົ້ນຫາ',
            Colors.deepOrange,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchScreen()))),
      if (Api.can('REPORT_VIEW'))
        _DashMenuItem(
            Icons.assessment_outlined,
            'ລາຍງານ',
            Colors.purple,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ReportsScreen()))),
      if (Api.can('STOCK_VIEW'))
        _DashMenuItem(
            Icons.event_note_outlined,
            'ແຜນຈັດຊື້ອາໄຫຼ່',
            Colors.indigo,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PurchasePlanPage()))),
      if (Api.can('TRANSFER_SEND') || Api.can('TRANSFER_RECEIVE'))
        _DashMenuItem(
            Icons.swap_horiz,
            'ໂອນສາຂາ',
            Colors.brown,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TransferScreen()))),
      if (Api.can('STOCK_COUNT'))
        _DashMenuItem(
            Icons.fact_check_outlined,
            'ນັບສະຕັອກ',
            Colors.cyan,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const StockCountPage()))),
    ];
    return GridView.count(
      crossAxisCount: 5,
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
      mainAxisSpacing: 12,
      childAspectRatio: 0.62,
      children: [
        for (final it in items)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: it.onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surface,
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Icon(it.icon, size: 30, color: it.color),
                ),
                const SizedBox(height: 8),
                Text(it.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------ Reports menu
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  Widget _card(BuildContext context, IconData icon, Color color, String title,
      String sub, List<String> chips, Widget page) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => page)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                    radius: 23,
                    backgroundColor: color.withOpacity(0.12),
                    child: Icon(icon, color: color)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(sub,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in chips)
                  Chip(
                      label: Text(c, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('ລາຍງານ',
              style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _card(
              context,
              Icons.inventory_2_outlined,
              Colors.blue,
              '1 · ລາຍງານສະຕັອກ',
              'Stock report',
              ['By brand', 'By product', 'By warehouse'],
              const StockReport()),
          const SizedBox(height: 12),
          _card(
              context,
              Icons.build_outlined,
              Colors.green,
              '2 · ຕູ້ ATM ທີ່ປ່ຽນອາໄຫຼ່',
              'ATM spare part change report',
              ['Date range', 'By ATM', 'By part'],
              const ReportAtmPartsPage()),
          const SizedBox(height: 12),
          _card(
              context,
              Icons.swap_horiz,
              Colors.brown,
              '3 · ລາຍງານໂອນອາໄຫຼ່ລະຫວ່າງສາຂາ',
              'Spare part transfer report',
              ['Date range', 'By branch', 'Status'],
              const TransferReportPage()),
        ],
      ),
    );
  }
}

class ReportStockPage extends StatelessWidget {
  const ReportStockPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('ລາຍງານສະຕັອກ')),
      body: const Center(child: Text('ກຳລັງພັດທະນາ')));
}

class ReportAtmPartsPage extends StatelessWidget {
  const ReportAtmPartsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('ຕູ້ ATM ທີ່ປ່ຽນອາໄຫຼ່')),
      body: const Center(child: Text('ກຳລັງພັດທະນາ')));
}

// ------------------------------------------------------------ Stock report
const String kStockReportEndpoint = '/stock/overview';

class ReportStockView extends StatefulWidget {
  const ReportStockView({super.key});
  @override
  State<ReportStockView> createState() => _ReportStockViewState();
}

class _ReportStockViewState extends State<ReportStockView> {
  late Future<dynamic> _f = Api.get(kStockReportEndpoint);
  String _q = '';
  String? _groupBy;

  void _reload() => setState(() {
        _f = Api.get(kStockReportEndpoint);
      });

  List<Map<String, dynamic>> _rows(dynamic d) {
    dynamic l = d;
    if (l is Map) {
      l = l.values.firstWhere((v) => v is List, orElse: () => const []);
    }
    if (l is! List) return [];
    return [
      for (final e in l)
        if (e is Map) Map<String, dynamic>.from(e)
    ];
  }

  bool _hide(String k) => k == 'id' || k.endsWith('_id') || k.endsWith('Id');

  String _fmt(dynamic v) {
    if (v == null) return '';
    if (v is double) {
      return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
    }
    return v.toString();
  }

  String _label(String c) => c == '_n' ? 'ລາຍການ' : c;

  String _csv(List<String> cols, List<Map<String, dynamic>> data) {
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer(cols.map((c) => q(_label(c))).join(','));
    for (final r in data) {
      b.write('\n');
      b.write(cols.map((c) => q(_fmt(r[c]))).join(','));
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: _f,
      builder: (context, snap) {
        Widget body;
        List<String> csvCols = [];
        List<Map<String, dynamic>> csvData = [];

        if (snap.connectionState != ConnectionState.done) {
          body = const Center(child: CircularProgressIndicator());
        } else if (snap.hasError) {
          body = Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${snap.error}', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _reload, child: const Text('ລອງໃໝ່')),
            ]),
          );
        } else {
          final all = _rows(snap.data);
          final first = all.isEmpty ? <String, dynamic>{} : all.first;
          final cols = first.keys
              .where((k) => !_hide(k) && first[k] is! Map && first[k] is! List)
              .toList();
          final numCols = cols
              .where((k) => all.every((r) => r[k] == null || r[k] is num))
              .toList();
          final textCols = cols.where((k) => !numCols.contains(k)).toList();

          final ql = _q.trim().toLowerCase();
          var data = ql.isEmpty
              ? all
              : all
                  .where((r) => cols
                      .any((c) => _fmt(r[c]).toLowerCase().contains(ql)))
                  .toList();
          var showCols = cols;
          var numShow = numCols;

          final g = _groupBy;
          if (g != null && textCols.contains(g)) {
            final m = <String, Map<String, dynamic>>{};
            for (final r in data) {
              final key = _fmt(r[g]);
              final row = m.putIfAbsent(key, () => {g: key, '_n': 0});
              row['_n'] = (row['_n'] as int) + 1;
              for (final c in numCols) {
                row[c] = ((row[c] ?? 0) as num) + ((r[c] ?? 0) as num);
              }
            }
            data = m.values.toList();
            showCols = [g, ...numCols, '_n'];
            numShow = [...numCols, '_n'];
          }

          csvCols = showCols;
          csvData = data;

          final totals = <String, num>{
            for (final c in numShow)
              c: data.fold<num>(0, (s, r) => s + ((r[c] ?? 0) as num)),
          };

          body = Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'ຄົ້ນຫາ',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String?>(
                    value: textCols.contains(_groupBy) ? _groupBy : null,
                    hint: const Text('ຈັດກຸ່ມ'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('ບໍ່ຈັດກຸ່ມ')),
                      for (final c in textCols)
                        DropdownMenuItem<String?>(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => setState(() => _groupBy = v),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${data.length} ແຖວ',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
              Expanded(
                child: data.isEmpty
                    ? const Center(child: Text('ບໍ່ມີຂໍ້ມູນ'))
                    : SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: [
                              for (final c in showCols)
                                DataColumn(
                                    label: Text(_label(c)),
                                    numeric: numShow.contains(c)),
                            ],
                            rows: [
                              for (final r in data)
                                DataRow(cells: [
                                  for (final c in showCols)
                                    DataCell(Text(_fmt(r[c]))),
                                ]),
                              DataRow(cells: [
                                for (final c in showCols)
                                  DataCell(Text(
                                    numShow.contains(c)
                                        ? _fmt(totals[c])
                                        : (c == showCols.first ? 'ລວມ' : ''),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  )),
                              ]),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('ລາຍງານສະຕັອກ',
                style: TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_all_outlined),
                tooltip: 'ຄັດລອກ CSV',
                onPressed: csvData.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(
                            ClipboardData(text: _csv(csvCols, csvData)));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ຄັດລອກແລ້ວ')));
                      },
              ),
              IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'ໂຫຼດໃໝ່',
                  onPressed: _reload),
            ],
          ),
          body: body,
        );
      },
    );
  }
}
