// Budget -> Excel (.xlsx) with product pictures, uses sharePoXlsx from po_excel.dart.
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'api.dart';
import 'po_excel.dart';
import 'product_images.dart' show productImageUrl;
import 'widgets.dart';

String _two(int n) => n < 10 ? '0$n' : '$n';

Object _q(num v) => v % 1 == 0 ? v.toInt() : v.toDouble();

Object _m(num v) => v.toDouble();

class _Thumb {
  final Uint8List bytes;
  final int w;
  final int h;
  const _Thumb(this.bytes, this.w, this.h);
}

// runs in a background isolate: any image type -> 48x48 jpg
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
        if (r != null) {
          out[u] = _Thumb(r[0] as Uint8List, r[1] as int, r[2] as int);
        }
      }
    } catch (e) {
      debugPrint('[BUDGET] image failed $u: $e');
    }
  }));
  return out;
}

Future<void> exportBudgetXlsx(Map<String, dynamic> d,
    {String branchName = '', String poText = '', String auditText = ''}) async {
  final years = asList(d['budgetByYear']);
  final items = asList(d['items']);
  final fm = num0(d['fm']).toInt();
  final pct = num0(d['pct']);

  final urls = <String>{};
  for (final it in items) {
    final u = productImageUrl(pick(it, ['imageUrl']));
    if (u.isNotEmpty) urls.add(u);
  }
  final thumbs = await _loadThumbs(urls);
  debugPrint('[BUDGET] images ${thumbs.length}/${urls.length}');

  final rows = <List<Object>>[];
  final bold = <int>{};
  final images = <XlImage>[];
  final heights = <int, double>{};
  void add(List<Object> r, {bool b = false}) {
    if (b) bold.add(rows.length);
    rows.add(r);
  }

  // settings + per-year budget (columns B, C)
  add(<Object>['', 'ງົບປະມານອາໄຫຼ່'], b: true);
  add(<Object>['', 'ສາຂາ', branchName.isEmpty ? 'ທຸກສາຂາ' : branchName]);
  add(<Object>['', 'ປີງົບປະມານ', fm == 1 ? 'ມັງກອນ - ທັນວາ' : 'ຕຸລາ - ກັນຍາ']);
  add(<Object>['', 'ຮອດສິ້ນປີ', num0(d['toYear']).toInt()]);
  add(<Object>['', 'ເຜື່ອ (%)', _q(pct)]);
  if (poText.isNotEmpty) add(<Object>['', 'PO', poText]);
  if (auditText.isNotEmpty) add(<Object>['', 'ໃບນັບສະຕັອກ', auditText]);
  add(<Object>['', 'ຄິດຈາກການໃຊ້ 12 ເດືອນຜ່ານມາ']);
  add(<Object>['', 'ຕ້ອງຊື້ = ໃຊ້ x % ຕ້ອງຊື້ ເພີມ - ຍັງໃນສາງ']);
  add(<Object>[]);
  add(<Object>['', 'ປີ', 'ງົບປະມານ'], b: true);
  for (final y in years) {
    add(<Object>['', '${y['label']}', _m(num0(y['amount']))]);
  }
  add(<Object>['', 'ລວມ', _m(num0(d['totalAmount']))], b: true);
  add(<Object>[]);

  add(<Object>[
    'ຮຸນ',
    'ຮູບ',
    'ສິນຄ້າ',
    'Barcode',
    'ປະເພດ',
    'ໜ່ວຍ',
    'ລາຄາ/ໜ່ວຍ',
    'ສະຕັອກ',
    'ເຄື່ອງຕົວຈິງ',
    'ໃຊ້',
    '% ຕ້ອງຊື້ ເພີມ',
    'ຕ້ອງຊື້',
    'ເງິນ',
  ], b: true);

  for (final it in items) {
    final u = productImageUrl(pick(it, ['imageUrl']));
    final t = thumbs[u];
    if (t != null) {
      images.add(XlImage(
          row: rows.length,
          col: 1,
          key: u,
          bytes: t.bytes,
          w: t.w,
          h: t.h));
      heights[rows.length] = 40.0;
    }
    add(<Object>[
      pick(it, ['models']),
      '',
      pick(it, ['productName']),
      pick(it, ['barcodes']),
      pick(it, ['typeName']),
      pick(it, ['unit']),
      _m(num0(it['unitCost'])),
      _q(num0(it['stock'])),
      it['counted'] == null ? '' : _q(num0(it['counted'])),
      _q(num0(it['ratePerYear'])),
      _q(pct),
      _q(num0(it['totalBuy'])),
      _m(num0(it['totalAmount'])),
    ]);
  }

  add(<Object>['', '', 'ລວມ', '', '', '', '', '', '', '', '', '', _m(num0(d['totalAmount']))],
      b: true);

  final widths = <double>[16, 12, 36, 17, 14, 10, 14, 12, 14, 12, 14, 14, 16];

  final n = DateTime.now();
  final fileName = 'budget_${n.year}${_two(n.month)}${_two(n.day)}.xlsx';
  await sharePoXlsx(
    fileName: fileName,
    rows: rows,
    boldRows: bold,
    widths: widths,
    images: images,
    rowHeights: heights,
  );
}
