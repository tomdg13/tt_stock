import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'api.dart';
import 'po_excel.dart';
import 'product_images.dart' show productImageUrl;

const bool _withOther = true;
const String _branchName = 'Head Office';
const String _toLine =
    'ຮຽນ: ທ່ານ ຫົວໜ້າຝ່າຍເຕັກໂນໂລຊີຂໍ້ມູນຂ່າວສານທີ່ນັບຖືຢ່າງສູງ';
const String _subjectLine = 'ເລື່ອງ: ຂໍຊື້ອາໄຫຼ່ເອທີເອັມ';
const String _closing1 =
    'ດັ່ງນັ້ນ ຈຶ່ງສະເໜີມາຍັງທ່ານເພື່ອພິຈາລະນາ ແລະ ແກ້ໄຂຕາມຄວາມເໝາະສົມດ້ວຍ.';
const String _closing2 = 'ຮຽນມາດ້ວຍຄວາມເຄົາລົບ ແລະ ນັບຖືຢ່າງສູງ.';
const String _sign1 = 'ຫົວໜ້າສາຂາ';
const String _sign2 = 'ຜູ້ສະເໜີ';
const String _newLabel = '(ເຄື່ອງທີ່ບໍ່ເຄີຍຊື້)';

const List<String> _months = [
  'ມັງກອນ',
  'ກຸມພາ',
  'ມີນາ',
  'ເມສາ',
  'ພຶດສະພາ',
  'ມິຖຸນາ',
  'ກໍລະກົດ',
  'ສິງຫາ',
  'ກັນຍາ',
  'ຕຸລາ',
  'ພະຈິກ',
  'ທັນວາ',
];

class _Thumb {
  final Uint8List bytes;
  final int w;
  final int h;
  const _Thumb(this.bytes, this.w, this.h);
}

List<Object>? _makeThumb(Uint8List b) {
  final im = img.decodeImage(b);
  if (im == null) return null;
  final sq = img.copyResizeCropSquare(im, size: 96);
  final jpg = Uint8List.fromList(img.encodeJpg(sq, quality: 78));
  return <Object>[jpg, 48, 48];
}

Future<Map<String, _Thumb>> _loadThumbs(Set<String> urls) async {
  final out = <String, _Thumb>{};
  final headers = Api.token == null
      ? <String, String>{}
      : <String, String>{'Authorization': 'Bearer ${Api.token}'};
  await Future.wait(urls.map((u) async {
    try {
      final res = await http
          .get(Uri.parse(u), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final r = await compute(_makeThumb, res.bodyBytes);
        if (r is List<Object>) {
          out[u] = _Thumb(r[0] as Uint8List, r[1] as int, r[2] as int);
        }
      }
    } catch (e) {
      debugPrint('[PLANXL] image failed $u: $e');
    }
  }));
  return out;
}

Object _qty(num v) => v % 1 == 0 ? v.toInt() : v.toDouble();

Object _numCell(dynamic v) => v is num ? _qty(v) : '-';

Object _posCell(dynamic v) => (v is num && v > 0) ? _qty(v) : '-';

String _two(int n) => n < 10 ? '0$n' : '$n';

String _brand(Map<String, dynamic> x) => '${x['brand'] ?? ''}';

String _nm(Map<String, dynamic> x) {
  final n = '${x['name'] ?? ''}';
  return x['isNew'] == true ? '$n\n$_newLabel' : n;
}

Future<void> exportPlanXlsx(
    Map<String, dynamic> plan, List<Map<String, dynamic>> items) async {
  final sel = items.where((x) => x['done'] == true).toList();
  if (sel.isEmpty) {
    throw Exception('ຍັງບໍ່ມີລາຍການທີ່ຕິກ');
  }
  sel.sort((a, b) {
    final c = _brand(a).compareTo(_brand(b));
    if (c == 0) return '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
    return c;
  });
  final count = <String, int>{};
  for (final x in sel) {
    count[_brand(x)] = (count[_brand(x)] ?? 0) + 1;
  }

  final urls = <String>{};
  for (final it in sel) {
    final u = productImageUrl('${it['imageUrl'] ?? ''}');
    if (u.isNotEmpty) urls.add(u);
  }
  final thumbs = await _loadThumbs(urls);
  debugPrint('[PLANXL] images ${thumbs.length}/${urls.length}');

  final rows = <List<Object>>[];
  final bold = <int>{};
  final images = <XlImage>[];
  final heights = <int, double>{};
  final tr = <int, int>{};
  void add(List<Object> r, {bool b = false}) {
    if (b) bold.add(rows.length);
    rows.add(r);
  }

  final n = DateTime.now();
  final dateLao = '${n.day} ${_months[n.month - 1]} ${n.year}';
  final planName = '${plan['name'] ?? ''}';
  final note = '${plan['note'] ?? ''}';

  add(<Object>['ສາຂາ $_branchName', '', '', '', 'ເລກທີ່: ................................']);
  add(<Object>['', '', '', '', '$_branchName, ວັນທີ $dateLao']);
  add(<Object>[]);
  add(<Object>['', '', 'ໜັງສືສະເໜີ'], b: true);
  add(<Object>[]);
  add(<Object>[_toLine]);
  add(<Object>[_subjectLine]);
  add(<Object>['- ອີງຕາມແຜນຊື້: $planName']);
  if (note.isNotEmpty) add(<Object>['- ໝາຍເຫດ: $note']);
  add(<Object>[
    'ສາຂາ $_branchName ຂໍຖືເປັນກຽດສະເໜີມາຍັງທ່ານເພື່ອຂໍຊື້ອາໄຫຼ່ເອທີເອັມ ຕາມລາຍລະອຽດດັ່ງລຸ່ມນີ້:'
  ]);
  add(<Object>[]);

  tr[rows.length] = 2;
  add(<Object>[
    'ລຳດັບ',
    'ຮູບ',
    'ສິນຄ້າ',
    'ສະຕັອກ',
    'ນັບຕົວຈິງ',
    'ໃຊ້',
    'ຕ້ອງຊື້',
    if (_withOther) 'ຊື້ມາແລ້ວ',
    'ຊື້ແຜນນີ້',
  ], b: true);

  var sumMust = 0.0;
  var sumBuy = 0.0;
  var no = 0;
  for (var i = 0; i < sel.length; i++) {
    final x = sel[i];
    final same = i > 0 && _brand(sel[i - 1]) == _brand(x);
    if (same == false) {
      final b = _brand(x);
      final label = b.isEmpty ? '(ບໍ່ມີ Brand)' : b;
      tr[rows.length] = 3;
      add(<Object>['', '', '$label (${count[b] ?? 0})'], b: true);
    }
    no++;
    final u = productImageUrl('${x['imageUrl'] ?? ''}');
    final t = thumbs[u];
    heights[rows.length] = 40.0;
    if (t is _Thumb) {
      images.add(XlImage(
          row: rows.length, col: 1, key: u, bytes: t.bytes, w: t.w, h: t.h));
      heights[rows.length] = 40.0;
    }
    final must = x['isNew'] == true ? null : (x['must'] ?? x['qty']);
    if (must is num) sumMust += must.toDouble();
    final buy = x['buyQty'];
    if (buy is num) sumBuy += buy.toDouble();
    tr[rows.length] = 1;
    add(<Object>[
      no,
      '',
      _nm(x),
      _numCell(x['stock']),
      _numCell(x['counted']),
      _numCell(x['used']),
      _numCell(must),
      if (_withOther) _posCell(x['other']),
      _numCell(buy),
    ]);
  }

  tr[rows.length] = 3;
  add(<Object>[
    '',
    '',
    'ລວມ ${sel.length} ລາຍການ',
    '',
    '',
    '',
    _qty(sumMust),
    if (_withOther) '',
    _qty(sumBuy),
  ], b: true);

  add(<Object>[]);
  add(<Object>[_closing1]);
  add(<Object>['', '', '', '', _closing2]);
  add(<Object>[]);
  add(<Object>['', '', _sign1, '', '', '', _sign2], b: true);
  add(<Object>[]);
  add(<Object>[]);
  add(<Object>[]);
  add(<Object>[]);

  final widths = <double>[8, 12, 70, 10, 12, 10, 10, if (_withOther) 12, 12];
  final fileName = 'buyplan_${n.year}${_two(n.month)}${_two(n.day)}.xlsx';
  await sharePoXlsx(
    fileName: fileName,
    rows: rows,
    boldRows: bold,
    widths: widths,
    images: images,
    rowHeights: heights,
    tableRows: tr,
    tableCols: _withOther ? 9 : 8,
    leftCols: const {2},
    boldCols: _withOther ? const {6, 8} : const {6, 7},
  );
}
