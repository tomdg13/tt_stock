import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'api.dart';
import 'po_excel.dart';
import 'product_images.dart' show productImageUrl;
import 'widgets.dart';

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

String _two(int n) => n < 10 ? '0$n' : '$n';

Future<void> exportPlanXlsx(
    Map<String, dynamic> plan, List<Map<String, dynamic>> items) async {
  final sorted = List<Map<String, dynamic>>.from(items);
  sorted.sort((a, b) {
    final c = '${a['brand'] ?? ''}'.compareTo('${b['brand'] ?? ''}');
    if (c == 0) return '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
    return c;
  });

  final urls = <String>{};
  for (final it in sorted) {
    final u = productImageUrl('${it['imageUrl'] ?? ''}');
    if (u.isNotEmpty) urls.add(u);
  }
  final thumbs = await _loadThumbs(urls);
  debugPrint('[PLANXL] images ${thumbs.length}/${urls.length}');

  final rows = <List<Object>>[];
  final bold = <int>{};
  final images = <XlImage>[];
  final heights = <int, double>{};
  void add(List<Object> r, {bool b = false}) {
    if (b) bold.add(rows.length);
    rows.add(r);
  }

  final created = '${plan['createdAt'] ?? ''}';
  final note = '${plan['note'] ?? ''}';
  final flt = '${plan['filter'] ?? ''}';
  final doneAll = sorted.where((x) => x['done'] == true).length;

  add(<Object>['${plan['name'] ?? ''}'], b: true);
  if (note.isNotEmpty) add(<Object>['ໝາຍເຫດ', note]);
  if (flt.isNotEmpty) add(<Object>['ຕົວກອງ', flt]);
  if (created.length >= 10) add(<Object>['ວັນທີສ້າງ', created.substring(0, 10)]);
  add(<Object>['ຊື້ແລ້ວ', '$doneAll / ${sorted.length}']);
  add(<Object>[]);

  add(<Object>[
    '#',
    'ຮູບ',
    'ສິນຄ້າ',
    'brand',
    'ທີ່ເກັບ',
    'ໜ່ວຍ',
    'ຈຳນວນ',
    'ສະຖານະ',
  ], b: true);

  final firstRow = rows.length + 1;
  var sumQ = 0.0;
  var no = 0;
  for (final it in sorted) {
    no++;
    final u = productImageUrl('${it['imageUrl'] ?? ''}');
    final t = thumbs[u];
    if (t is _Thumb) {
      images.add(XlImage(
          row: rows.length, col: 1, key: u, bytes: t.bytes, w: t.w, h: t.h));
      heights[rows.length] = 40.0;
    }
    final q = num0(it['qty']).toDouble();
    sumQ += q;
    add(<Object>[
      no,
      '',
      '${it['name'] ?? ''}',
      '${it['brand'] ?? ''}',
      '${it['bin'] ?? ''}',
      '${it['unit'] ?? ''}',
      _qty(q),
      it['done'] == true ? 'ຊື້ແລ້ວ' : 'ຍັງບໍ່ຊື້',
    ]);
  }
  final lastRow = rows.length;

  add(<Object>[
    '',
    '',
    'ລວມ',
    '',
    '',
    '',
    XlFormula('SUM(G$firstRow:G$lastRow)', sumQ),
    '',
  ], b: true);

  final widths = <double>[6, 12, 60, 18, 14, 10, 12, 14];
  final n = DateTime.now();
  final fileName = 'buyplan_${n.year}${_two(n.month)}${_two(n.day)}.xlsx';
  await sharePoXlsx(
    fileName: fileName,
    rows: rows,
    boldRows: bold,
    widths: widths,
    images: images,
    rowHeights: heights,
  );
}
