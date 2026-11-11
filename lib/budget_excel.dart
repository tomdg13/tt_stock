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
  final past = asList(d['pastYears']);
  final future = asList(d['futureYears']);
  final years = asList(d['budgetByYear']);
  final items = asList(d['items']);
  final fm = num0(d['fm']).toInt();

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

  // settings + summary
  add(<Object>['ງົບປະມານອາໄຫຼ່'], b: true);
  add(<Object>['ສາຂາ', branchName.isEmpty ? 'ທຸກສາຂາ' : branchName]);
  add(<Object>['ປີງົບປະມານ', fm == 1 ? 'ມັງກອນ - ທັນວາ' : 'ຕຸລາ - ກັນຍາ']);
  add(<Object>['ຮອດສິ້ນປີ', num0(d['toYear']).toInt()]);
  add(<Object>['ເຜື່ອ (%)', num0(d['pct']).toInt()]);
  if (poText.isNotEmpty) add(<Object>['PO', poText]);
  if (auditText.isNotEmpty) add(<Object>['ໃບນັບສະຕັອກ', auditText]);
  add(<Object>['ຄິດຈາກການໃຊ້ 12 ເດືອນຜ່ານມາ']);
  add(<Object>[]);
  add(<Object>['ປີ', 'ງົບປະມານ'], b: true);
  for (final y in years) {
    add(<Object>['${y['label']}', _m(num0(y['amount']))]);
  }
  add(<Object>['ລວມ', _m(num0(d['totalAmount']))], b: true);
  add(<Object>[]);

  // item table header (column A = picture)
  final head = <Object>[
    'ຮູບ',
    'ສິນຄ້າ',
    'ໜ່ວຍ',
    'ລາຄາ/ໜ່ວຍ',
    'ສະຕັອກ',
    'ເຄື່ອງຕົວຈິງ',
    'ຊື້ທັງໝົດ (PO)',
    'PO ຄ້າງຮັບ',
    'ໃຊ້/ປີ',
  ];
  for (final p in past) {
    head.add('ຊື້ ${p['label']}');
    head.add('ໃຊ້ ${p['label']}');
  }
  for (final f in future) {
    head.add('ຕ້ອງໃຊ້ ${f['label']}');
    head.add('ຕ້ອງຊື້ ${f['label']}');
    head.add('ເງິນ ${f['label']}');
  }
  head.add('ຄວນຊື້ (ລວມ)');
  head.add('ລວມເງິນ');
  add(head, b: true);

  // item rows
  for (final it in items) {
    final bought = (it['bought'] as List?) ?? const [];
    final used = (it['used'] as List?) ?? const [];
    final plan = asList(it['plan']);

    final u = productImageUrl(pick(it, ['imageUrl']));
    final t = thumbs[u];
    if (t != null) {
      images.add(XlImage(
          row: rows.length,
          col: 0,
          key: u,
          bytes: t.bytes,
          w: t.w,
          h: t.h));
      heights[rows.length] = 40.0;
    }

    final r = <Object>[
      '',
      pick(it, ['productName']),
      pick(it, ['unit']),
      _m(num0(it['unitCost'])),
      _q(num0(it['stock'])),
      it['counted'] == null ? '' : _q(num0(it['counted'])),
      _q(num0(it['poTotal'])),
      _q(num0(it['ordered'])),
      _q(num0(it['ratePerYear'])),
    ];
    for (var i = 0; i < past.length; i++) {
      r.add(_q(i < bought.length ? num0(bought[i]) : 0));
      r.add(_q(i < used.length ? num0(used[i]) : 0));
    }
    for (var i = 0; i < future.length; i++) {
      if (i < plan.length) {
        r.add(_q(num0(plan[i]['need'])));
        r.add(_q(num0(plan[i]['buy'])));
        r.add(_m(num0(plan[i]['amount'])));
      } else {
        r.add(0);
        r.add(0);
        r.add(_m(0));
      }
    }
    r.add(_q(num0(it['totalBuy'])));
    r.add(_m(num0(it['totalAmount'])));
    add(r);
  }

  // total row (amount columns only, units differ per item)
  final tot = <Object>['', 'ລວມ', '', '', '', '', '', '', ''];
  for (var i = 0; i < past.length; i++) {
    tot.add('');
    tot.add('');
  }
  for (var i = 0; i < future.length; i++) {
    tot.add('');
    tot.add('');
    tot.add(_m(i < years.length ? num0(years[i]['amount']) : 0));
  }
  tot.add('');
  tot.add(_m(num0(d['totalAmount'])));
  add(tot, b: true);

  final widths = <double>[16, 36, 10, 14, 12, 14, 14, 12, 12];
  for (var i = 0; i < past.length; i++) {
    widths.add(12);
    widths.add(12);
  }
  for (var i = 0; i < future.length; i++) {
    widths.add(12);
    widths.add(12);
    widths.add(16);
  }
  widths.add(14);
  widths.add(18);

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
