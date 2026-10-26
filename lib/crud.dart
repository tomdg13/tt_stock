// ignore_for_file: camel_case_types
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'lao.dart';
import 'pages.dart';
import 'product_images.dart';
import 'product_barcodes.dart';
import 'type_image.dart';
import 'theme.dart';
import 'widgets.dart';

typedef Row_ = Map<String, dynamic>;
typedef Opt = MapEntry<dynamic, String>;

enum FT { text, number, pin, bool, select, multi, matrix }

class FieldSpec {
  final String key, label;
  final FT type;
  final bool required, onlyAdd, onlyEdit;
  final String? optionsPath; // GET list used for select / multi
  final String optionValue;
  final List<String> optionLabels;
  final Map<dynamic, String>? options; // static options
  final List<String> altKeys; // other names the server may use when reading
  final (String, String)? hideIf; // hide + omit when field (key) equals value
  final (
    String,
    String
  )? requiredUnless; // required unless field (key) equals value
  final String?
      nameKey; // row key holding the option label (used when the id is missing)
  const FieldSpec(
    this.key,
    this.label, {
    this.type = FT.text,
    this.required = false,
    this.onlyAdd = false,
    this.onlyEdit = false,
    this.optionsPath,
    this.optionValue = 'id',
    this.optionLabels = const ['name'],
    this.options,
    this.altKeys = const [],
    this.hideIf,
    this.requiredUnless,
    this.nameKey,
  });
}

class RowAction {
  final String label;
  final IconData icon;
  final String? perm;
  final Future<void> Function(BuildContext, Row_) run;
  const RowAction(this.label, this.icon, this.run, {this.perm});
}

class CrudSpec {
  final String title, path;
  final String Function(Row_) idOf;
  final List<FieldSpec> fields;
  final List<String> titleKeys, subKeys, tagKeys, trailKeys;
  final String? writePerm;
  final bool searchable, canAdd, canDelete, canEdit;
  final String? listPath; // GET list path when it differs from [path]
  final String extraQuery;
  final String Function(Row_)? detailPath;
  final List<RowAction> actions;
  final bool images; // show the image picker in the form
  final bool barcodes; // barcode list in the form
  final bool typeImage; // single picture (terminal type form)
  const CrudSpec({
    required this.title,
    required this.path,
    required this.idOf,
    required this.fields,
    required this.titleKeys,
    this.subKeys = const [],
    this.tagKeys = const [],
    this.trailKeys = const [],
    this.writePerm,
    this.searchable = true,
    this.canAdd = true,
    this.canDelete = true,
    this.canEdit = true,
    this.listPath,
    this.extraQuery = '',
    this.detailPath,
    this.actions = const [],
    this.images = false,
    this.barcodes = false,
    this.typeImage = false,
  });

  bool get canWrite => writePerm == null || Api.can(writePerm!);
}

String _enc(String s) => Uri.encodeComponent(s);

void toastMsg(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

const _valueAlts = ['funcCode', 'code', 'roleName', 'name', 'id'];
const _labelAlts = [
  'roleLabel',
  'funcName',
  'name',
  'label',
  'description',
  'title',
  'roleName',
  'code'
];

/// Loads a list for a dropdown / checkbox group. Tolerates servers that use
/// other key names than [valueKey] (e.g. funcCode instead of id).
Future<List<Opt>> loadOptions(
    String path, String valueKey, List<String> labelKeys) async {
  final rows = asList(await Api.get(path));
  final out = <Opt>[];
  for (final r in rows) {
    dynamic v = r[valueKey];
    if (v == null) {
      for (final k in _valueAlts) {
        if (r[k] != null) {
          v = r[k];
          break;
        }
      }
    }
    if (v == null) {
      for (final x in r.values) {
        if (x != null && x is! Map && x is! List) {
          v = x;
          break;
        }
      }
    }
    if (v == null) continue;
    var label = pick(r, [...labelKeys, ..._labelAlts]);
    final lao = permLabels['$v'];
    if (lao != null) label = lao;
    out.add(MapEntry(v, label.isEmpty ? '$v' : label));
  }
  return out;
}

dynamic _match(List<Opt> opts, dynamic v) {
  for (final o in opts) {
    if ('${o.key}' == '$v') return o.key;
  }
  return v;
}

bool _truthy(dynamic v) =>
    v == true ||
    v == 1 ||
    '$v' == '1' ||
    '$v'.toLowerCase() == 'true' ||
    '$v' == 'Y';

/// Ask for confirmation, call DELETE, return true when the row was deleted.
Future<bool> confirmDelete(BuildContext context, CrudSpec sp, Row_ row) async {
  final name = pick(row, sp.titleKeys);
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('ຢືນຢັນການລຶບ'),
      content: Text('ລຶບ "$name" ແທ້ບໍ?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('ຍົກເລີກ')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: pal(c).bad, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('ລຶບ'),
        ),
      ],
    ),
  );
  if (yes != true) return false;
  try {
    await Api.delete('${sp.path}/${_enc(sp.idOf(row))}');
    if (context.mounted) toastMsg(context, 'ລຶບແລ້ວ');
    return true;
  } catch (e) {
    if (context.mounted) toastMsg(context, '$e');
    return false;
  }
}

/// Open the edit form (loading the full record first when there is a detail route).
Future<bool> openEdit(BuildContext context, CrudSpec sp, Row_ row) async {
  var cur = row;
  if (sp.detailPath != null) {
    try {
      final d = await Api.get(sp.detailPath!(row));
      if (d is Map) cur = Row_.from(d);
    } catch (_) {}
  }
  if (!context.mounted) return false;
  final ok = await Navigator.push<bool>(
      context, MaterialPageRoute(builder: (_) => CrudForm(sp, row: cur)));
  return ok == true;
}

// ------------------------------------------------------------ list page
class CrudPage extends StatefulWidget {
  final CrudSpec spec;
  const CrudPage(this.spec, {super.key});
  @override
  State<CrudPage> createState() => _CrudPageState();
}

class _CrudPageState extends State<CrudPage> {
  final _signal = ValueNotifier<int>(0);
  void _reload() => _signal.value++;

  Future<void> _add() async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => CrudForm(widget.spec)));
    if (ok == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final sp = widget.spec;
    final p = pal(context);
    final canW = sp.canWrite;
    final showRowBtns = canW && (sp.canEdit || sp.canDelete);
    return Column(children: [
      if (sp.canAdd && canW)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(
              child: Text(sp.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('ເພີ່ມ'),
            ),
          ]),
        ),
      Expanded(
        child: ListPage(
          title: sp.title,
          path: sp.listPath ?? sp.path,
          titleKeys: sp.titleKeys,
          subKeys: sp.subKeys,
          tagKeys: sp.tagKeys,
          trailKeys: sp.trailKeys,
          searchable: sp.searchable,
          extraQuery: sp.extraQuery,
          reloadSignal: _signal,
          onTapItem: (ctx, row) => Navigator.push(
            ctx,
            MaterialPageRoute(
                builder: (_) => CrudDetail(sp, row, onChanged: _reload)),
          ),
          rowActions: showRowBtns
              ? (ctx, row) => Row(mainAxisSize: MainAxisSize.min, children: [
                    if (sp.canEdit)
                      IconButton(
                        icon: Icon(Icons.edit_outlined, size: 20, color: p.pri),
                        tooltip: 'ແກ້ໄຂ',
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          if (await openEdit(ctx, sp, row)) _reload();
                        },
                      ),
                    if (sp.canDelete)
                      IconButton(
                        icon:
                            Icon(Icons.delete_outline, size: 20, color: p.bad),
                        tooltip: 'ລຶບ',
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          if (await confirmDelete(ctx, sp, row)) _reload();
                        },
                      ),
                  ])
              : null,
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------- detail page
class CrudDetail extends StatefulWidget {
  final CrudSpec spec;
  final Row_ row;
  final VoidCallback onChanged;
  const CrudDetail(this.spec, this.row, {super.key, required this.onChanged});
  @override
  State<CrudDetail> createState() => _CrudDetailState();
}

class _CrudDetailState extends State<CrudDetail> {
  late Future<dynamic> _f = _load();

  Future<dynamic> _load() async {
    final dp = widget.spec.detailPath;
    return dp == null ? widget.row : await Api.get(dp(widget.row));
  }

  void _reload() => setState(() {
        _f = _load();
      });

  Future<Row_> _current() async {
    final d = await _f;
    return d is Map ? Row_.from(d) : widget.row;
  }

  Future<void> _edit() async {
    final cur = await _current();
    if (!mounted) return;
    final ok = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => CrudForm(widget.spec, row: cur)));
    if (ok == true) {
      widget.onChanged();
      _reload();
    }
  }

  Future<void> _delete() async {
    if (await confirmDelete(context, widget.spec, widget.row)) {
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = widget.spec;
    final p = pal(context);
    final title = pick(widget.row, sp.titleKeys);
    return Scaffold(
      appBar: AppBar(
        title: Text(title.isEmpty ? sp.title : title),
        actions: [
          if (sp.canWrite && sp.canEdit)
            IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'ແກ້ໄຂ',
                onPressed: _edit),
          if (sp.canWrite && sp.canDelete)
            IconButton(
                icon: Icon(Icons.delete_outline, color: p.bad),
                tooltip: 'ລຶບ',
                onPressed: _delete),
        ],
      ),
      body: FutureBuilder(
        future: _f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) return ErrorView(s.error!, _reload);
          final acts = sp.actions
              .where((a) => a.perm == null || Api.can(a.perm!))
              .toList();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (acts.isNotEmpty)
                AppCard(
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final a in acts)
                      OutlinedButton.icon(
                        icon: Icon(a.icon, size: 18),
                        label: Text(a.label),
                        onPressed: () async {
                          final cur = await _current();
                          if (!context.mounted) return;
                          await a.run(context, cur);
                          widget.onChanged();
                          _reload();
                        },
                      ),
                  ]),
                ),
              if (s.data is Map &&
                  (s.data as Map)['images'] is List &&
                  ((s.data as Map)['images'] as List).isNotEmpty)
                AppCard(
                    title: 'ຮູບພາບ',
                    child:
                        ProductImageStrip(asList((s.data as Map)['images']))),
              AppCard(child: DataView(s.data)),
            ]),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------ form page
class CrudForm extends StatefulWidget {
  final CrudSpec spec;
  final Row_? row;
  final Row_? initial; // pre-filled values when adding
  const CrudForm(this.spec, {super.key, this.row, this.initial});
  @override
  State<CrudForm> createState() => _CrudFormState();
}

class _CrudFormState extends State<CrudForm> {
  final _ctl = <String, TextEditingController>{};
  final _v = <String, dynamic>{};
  final _opts = <String, List<Opt>>{};
  final _json = TextEditingController();
  final _imgs = ProductImagesController();
  final _bcs = ProductBarcodesController();
  final _timg = TypeImageController();
  bool _jsonMode = false, _busy = false;
  String? _error;

  bool get _editing => widget.row != null;

  bool _hidden(FieldSpec f) =>
      f.hideIf != null && '${_v[f.hideIf!.$1]}' == f.hideIf!.$2;
  bool _req(FieldSpec f) =>
      f.required ||
      (f.requiredUnless != null &&
          '${_v[f.requiredUnless!.$1]}' != f.requiredUnless!.$2);
  List<FieldSpec> get _visible => _fields.where((f) => !_hidden(f)).toList();
  List<FieldSpec> get _fields => widget.spec.fields
      .where((f) => !(f.onlyAdd && _editing) && !(f.onlyEdit && !_editing))
      .toList();

  dynamic _read(FieldSpec f) {
    final r = widget.row ?? widget.initial;
    if (r == null) return null;
    for (final k in [f.key, ...f.altKeys]) {
      if (r[k] != null) return r[k];
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      final cur = _read(f);
      if (f.type == FT.text || f.type == FT.number || f.type == FT.pin) {
        _ctl[f.key] = TextEditingController(
            text: f.type == FT.pin || cur == null ? '' : '$cur');
      } else if (f.type == FT.bool) {
        _v[f.key] = cur == null ? true : _truthy(cur);
      } else if (f.type == FT.multi || f.type == FT.matrix) {
        _v[f.key] = cur is List
            ? [
                for (final x in cur)
                  x is Map
                      ? (x['id'] ?? x['code'] ?? x['funcCode'] ?? x['name'])
                      : x
              ]
            : <dynamic>[];
      } else {
        _v[f.key] = cur;
      }
      if (f.type == FT.select || f.type == FT.multi) {
        if (f.options != null) {
          _opts[f.key] = [
            for (final e in f.options!.entries) MapEntry(e.key, e.value)
          ];
          _normalize(f);
        } else if (f.optionsPath != null) {
          loadOptions(f.optionsPath!, f.optionValue, f.optionLabels).then((o) {
            if (!mounted) return;
            setState(() {
              _opts[f.key] = o;
              _normalize(f);
            });
          }).catchError((_) {});
        }
      }
    }
  }

  void _normalize(FieldSpec f) {
    final o = _opts[f.key] ?? [];
    if (f.type == FT.select && _v[f.key] != null)
      _v[f.key] = _match(o, _v[f.key]);
    if (f.type == FT.select &&
        _v[f.key] == null &&
        f.nameKey != null &&
        widget.row != null) {
      final nm = '${widget.row![f.nameKey] ?? ''}'.trim().toLowerCase();
      if (nm.isNotEmpty) {
        for (final e in o) {
          if (e.value.trim().toLowerCase() == nm) {
            _v[f.key] = e.key;
            break;
          }
        }
      }
    }
    if (f.type == FT.multi)
      _v[f.key] = [for (final x in _v[f.key] as List) _match(o, x)];
  }

  /// Returns the request body, or sets _error and returns null.
  Row_? _body() {
    final b = <String, dynamic>{};
    for (final f in _visible) {
      final t = _ctl[f.key]?.text.trim() ?? '';
      switch (f.type) {
        case FT.text:
          if (t.isNotEmpty) b[f.key] = t;
          break;
        case FT.number:
          if (t.isNotEmpty) {
            final n = num.tryParse(t);
            if (n == null) {
              _error = '${f.label}: ຕ້ອງເປັນຕົວເລກ';
              return null;
            }
            b[f.key] = n;
          }
          break;
        case FT.pin:
          if (t.isNotEmpty) {
            if (t.length < 4) {
              _error = 'PIN ຕ້ອງມີ 4-6 ໂຕເລກ';
              return null;
            }
            b[f.key] = t;
          }
          break;
        case FT.bool:
          b[f.key] = _v[f.key] == true;
          break;
        case FT.select:
          if (_v[f.key] != null) b[f.key] = _v[f.key];
          break;
        case FT.multi:
        case FT.matrix:
          b[f.key] = List<dynamic>.from(_v[f.key] as List);
          break;
      }
      final missing = _req(f) &&
          (f.type == FT.select
              ? _v[f.key] == null
              : (f.type == FT.text ||
                      f.type == FT.number ||
                      f.type == FT.pin) &&
                  t.isEmpty);
      if (missing && !(f.type == FT.pin && _editing)) {
        _error = 'ກະລຸນາໃສ່ ${f.label}';
        return null;
      }
    }
    return b;
  }

  void _toggleJson(bool on) {
    if (on) {
      _error = null;
      final b = _body();
      if (b == null) {
        setState(() {});
        return;
      }
      _json.text = const JsonEncoder.withIndent('  ').convert(b);
    }
    setState(() {
      _jsonMode = on;
    });
  }

  Future<void> _save() async {
    Row_? body;
    setState(() {
      _error = null;
    });
    if (_jsonMode) {
      try {
        body = Row_.from(jsonDecode(_json.text) as Map);
      } catch (_) {
        setState(() {
          _error = 'JSON ບໍ່ຖືກຕ້ອງ';
        });
        return;
      }
    } else {
      body = _body();
      if (body == null) {
        setState(() {});
        return;
      }
    }
    setState(() {
      _busy = true;
    });
    try {
      final sp = widget.spec;
      String savedId;
      if (_editing) {
        savedId = sp.idOf(widget.row!);
        await Api.put('${sp.path}/${_enc(savedId)}', body);
      } else {
        final res = await Api.post(sp.path, body);
        savedId = res is Map ? pick(res, ['id', 'productId', 'typeId']) : '';
        if (savedId.isEmpty && body['id'] != null) savedId = '${body['id']}';
        if (savedId.isEmpty && res is Map && res['data'] is Map) {
          savedId = pick(res['data'] as Map, ['id', 'productId']);
        }
      }
      String? imgErr;
      if (sp.images && _imgs.pending.isNotEmpty) {
        if (savedId.isEmpty) {
          imgErr = 'ບໍ່ພົບ id ສິນຄ້າ';
        } else {
          try {
            await _imgs.uploadAll(savedId);
          } catch (e) {
            imgErr = '$e';
          }
        }
      }
      if (sp.barcodes && _bcs.dirty) {
        if (savedId.isEmpty) {
          imgErr = 'ບໍ່ພົບ id';
        } else {
          try {
            await _bcs.apply(savedId);
          } catch (e) {
            imgErr = '$e';
          }
        }
      }
      if (sp.typeImage && _timg.dirty) {
        if (savedId.isEmpty) {
          imgErr = 'ບໍ່ພົບ id';
        } else {
          try {
            await _timg.apply(savedId);
          } catch (e) {
            imgErr = '$e';
          }
        }
      }
      if (!mounted) return;
      toastMsg(
          context,
          imgErr == null
              ? 'ບັນທຶກແລ້ວ'
              : 'ບັນທຶກສິນຄ້າແລ້ວ ແຕ່ບາງຢ່າງບໍ່ສຳເລັດ: $imgErr');
      Navigator.pop(context, true);
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

  Widget _field(FieldSpec f) {
    final p = pal(context);
    final label = _req(f) ? '${f.label} *' : f.label;
    switch (f.type) {
      case FT.bool:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _v[f.key] == true,
          onChanged: (v) => setState(() {
            _v[f.key] = v;
          }),
        );
      case FT.select:
        final o = _opts[f.key] ?? [];
        final cur = o.any((e) => e.key == _v[f.key]) ? _v[f.key] : null;
        return DropdownButtonFormField<dynamic>(
          key: ValueKey('${f.key}-${o.length}-$cur'),
          initialValue: cur,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            if (!_req(f)) const DropdownMenuItem(value: null, child: Text('-')),
            for (final e in o)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() {
            _v[f.key] = v;
          }),
        );
      case FT.matrix:
        return _matrix(f);
      case FT.multi:
        final o = _opts[f.key] ?? [];
        final sel = _v[f.key] as List;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: p.mut, fontSize: 14)),
          const SizedBox(height: 6),
          if (o.isEmpty) Text('...', style: TextStyle(color: p.mut)),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in o)
              FilterChip(
                label: Text(e.value),
                selected: sel.contains(e.key),
                onSelected: (on) => setState(() {
                  if (on) {
                    sel.add(e.key);
                  } else {
                    sel.remove(e.key);
                  }
                }),
              ),
          ]),
        ]);
      default:
        return TextField(
          controller: _ctl[f.key],
          obscureText: f.type == FT.pin,
          keyboardType:
              f.type == FT.text ? TextInputType.text : TextInputType.number,
          inputFormatters: f.type == FT.pin
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          maxLength: f.type == FT.pin ? 6 : null,
          decoration: InputDecoration(
              labelText: f.type == FT.pin && _editing
                  ? '${f.label} (ເວົ້ນວ່າງ = ບໍ່ປ່ຽນ)'
                  : label,
              counterText: ''),
        );
    }
  }

  /// Page x (View / Edit / Delete) table, backed by the API's permission codes.
  Widget _matrix(FieldSpec f) {
    final p = pal(context);
    final sel = _v[f.key] as List;
    bool isOn(String c) => sel.any((x) => '$x' == c);
    // true = all selected, null = some selected, false = none
    bool? state(List<String> codes) {
      if (codes.isEmpty) return false;
      final n = codes.where(isOn).length;
      return n == 0 ? false : (n == codes.length ? true : null);
    }

    void toggle(List<String> codes) => setState(() {
          if (state(codes) == true) {
            sel.removeWhere((x) => codes.contains('$x'));
          } else {
            for (final c in codes) {
              if (!isOn(c)) sel.add(c);
            }
          }
        });
    List<String> uniq(Iterable<List<String>> lists) =>
        {for (final l in lists) ...l}.toList();

    final viewAll = uniq(permPages.map((e) => e.view));
    final editAll = uniq(permPages.map((e) => e.edit));
    final delAll = uniq(permPages.map((e) => e.del));
    final every = uniq([viewAll, editAll, delAll]);

    Widget cell(List<String> codes) => SizedBox(
          width: 52,
          child: codes.isEmpty
              ? Center(child: Text('–', style: TextStyle(color: p.mut)))
              : Checkbox(
                  tristate: true,
                  value: state(codes),
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => toggle(codes),
                ),
        );
    Widget head(String t, List<String> codes) => SizedBox(
          width: 52,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: p.mut)),
            Checkbox(
              tristate: true,
              value: state(codes),
              visualDensity: VisualDensity.compact,
              onChanged: (_) => toggle(codes),
            ),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(f.label, style: TextStyle(color: p.mut, fontSize: 14)),
      const SizedBox(height: 6),
      InkWell(
        onTap: () => toggle(every),
        child: Row(children: [
          Checkbox(
            tristate: true,
            value: state(every),
            visualDensity: VisualDensity.compact,
            onChanged: (_) => toggle(every),
          ),
          const Text('ເລືອກທັງໝົດ',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
      Divider(height: 8, color: p.bd),
      Row(children: [
        const Expanded(child: SizedBox()),
        head('ເບິ່ງ', viewAll),
        head('ແກ້ໄຂ', editAll),
        head('ລຶບ', delAll),
      ]),
      Divider(height: 8, color: p.bd),
      for (final pg in permPages)
        Container(
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: p.bd))),
          child: Row(children: [
            Expanded(
              child: InkWell(
                onTap: () => toggle(uniq([pg.view, pg.edit, pg.del])),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(pg.label, style: const TextStyle(fontSize: 14)),
                ),
              ),
            ),
            cell(pg.view),
            cell(pg.edit),
            cell(pg.del),
          ]),
        ),
      const SizedBox(height: 8),
      Text(
          'ກົດຫົວຄໍລຳເພື່ອເລືອກທັງຄໍລຳ, ກົດຊື່ແຖວເພື່ອເລືອກທັງແຖວ. ຊ່ອງທີ່ໃຊ້ສິດດຽວກັນຈະປ່ຽນພ້ອມກັນ',
          style: TextStyle(color: p.mut, fontSize: 12)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(
          title: Text('${_editing ? 'ແກ້ໄຂ' : 'ເພີ່ມ'} ${widget.spec.title}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_jsonMode)
              TextField(
                controller: _json,
                maxLines: 14,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(labelText: 'JSON'),
              )
            else
              for (final f in _visible) ...[
                _field(f),
                const SizedBox(height: 12)
              ],
            if (widget.spec.barcodes && !_jsonMode) ...[
              ProductBarcodesEditor(
                productId: _editing ? widget.spec.idOf(widget.row!) : null,
                controller: _bcs,
              ),
              const SizedBox(height: 12),
            ],
            if (widget.spec.images && !_jsonMode) ...[
              ProductImagesEditor(
                productId: _editing ? widget.spec.idOf(widget.row!) : null,
                controller: _imgs,
              ),
              const SizedBox(height: 12),
            ],
            if (widget.spec.typeImage && !_jsonMode) ...[
              TypeImageEditor(
                existingFile: _editing ? pick(widget.row!, ['imageFile']) : '',
                controller: _timg,
              ),
              const SizedBox(height: 12),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: p.bad)),
              ),
            saveButton('ບັນທຶກ', _busy, _save),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('ແກ້ເປັນ JSON (ຂັ້ນສູງ)',
                  style: TextStyle(color: p.mut, fontSize: 13)),
              value: _jsonMode,
              onChanged: _toggleJson,
            ),
          ]),
        ),
      ]),
    );
  }
}

// -------------------------------------------------------- pick dialogs
Future<List<dynamic>?> pickMulti(
    BuildContext context, String title, List<Opt> opts, List<dynamic> initial) {
  final sel = <dynamic>[...initial];
  return showDialog<List<dynamic>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            for (final o in opts)
              CheckboxListTile(
                dense: true,
                title: Text(o.value),
                value: sel.any((x) => '$x' == '${o.key}'),
                onChanged: (on) => set(() {
                  if (on == true) {
                    sel.add(o.key);
                  } else {
                    sel.removeWhere((x) => '$x' == '${o.key}');
                  }
                }),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(c, sel),
              child: const Text('ບັນທຶກ')),
        ],
      ),
    ),
  );
}

Future<String?> pickOne(BuildContext context, String title, List<String> values,
    [String? current]) {
  return showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(title),
      children: [
        for (final v in values)
          ListTile(
            dense: true,
            title: Text(v),
            trailing: v == current ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(c, v),
          ),
      ],
    ),
  );
}
