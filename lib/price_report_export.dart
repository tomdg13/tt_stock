import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextDirection;
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'branch_price_table.dart';
import 'po_excel.dart';
import 'ldb_letterhead.dart';

class PriceReportData {
  final String range;
  final String branch;
  final List<BranchPriceRow> rows;
  final List<dynamic> pos;
  final List<dynamic> items;
  final List<dynamic> used;
  final String Function(dynamic row, String nameKey) imgFor;
  const PriceReportData({
    required this.range,
    required this.branch,
    required this.rows,
    required this.pos,
    required this.items,
    required this.used,
    required this.imgFor,
  });
}

class _Ln {
  final List<Object> cells;
  final String url;
  const _Ln(this.cells, this.url);
}

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
  await Future.wait(urls.map((u) async {
    try {
      final res =
          await http.get(Uri.parse(u)).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final r = await compute(_makeThumb, res.bodyBytes);
        if (r != null) {
          out[u] = _Thumb(r[0] as Uint8List, r[1] as int, r[2] as int);
        }
      }
    } catch (e) {
      debugPrint('[REPORT] image failed $u: $e');
    }
  }));
  return out;
}

// ---- Lao text drawn by Flutter (correct shaping) and placed as images ----

class _TxtImg {
  final Uint8List bytes;
  final double w;
  final double h;
  const _TxtImg(this.bytes, this.w, this.h);
}

const double _sc = 4.0;
final RegExp _laoRe = RegExp(r'[\u0E80-\u0EFF]');
final Map<String, _TxtImg> _txtCache = {};
bool _fontReady = false;

Future<void> _ensureFont() async {
  if (_fontReady) return;
  final a = FontLoader('PhetsarathRep')
    ..addFont(rootBundle.load('assets/fonts/Phetsarath-OT.ttf'));
  await a.load();
  final b = FontLoader('PhetsarathRepBold')
    ..addFont(rootBundle.load('assets/fonts/Phetsarath-OT-Bold.ttf'));
  await b.load();
  _fontReady = true;
}

Future<void> _renderLao(String t, double size, bool bold) async {
  final key = '${bold ? 1 : 0}|$size|$t';
  if (_txtCache.containsKey(key)) return;
  final tp = TextPainter(
    text: TextSpan(
        text: t,
        style: TextStyle(
            fontFamily: bold ? 'PhetsarathRepBold' : 'PhetsarathRep',
            fontSize: size * _sc,
            color: const ui.Color(0xFF000000))),
    textDirection: TextDirection.ltr,
  );
  tp.layout();
  final w = tp.width.ceil() + 2;
  final h = tp.height.ceil() + 2;
  final rec = ui.PictureRecorder();
  final cv = ui.Canvas(rec);
  tp.paint(cv, const ui.Offset(1, 1));
  final im = await rec.endRecording().toImage(w, h);
  final bd = await im.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) return;
  _txtCache[key] =
      _TxtImg(bd.buffer.asUint8List(), w.toDouble() / _sc, h.toDouble() / _sc);
}

Future<void> _prepLao(Set<String> all) async {
  await _ensureFont();
  for (final t in all) {
    if (_laoRe.hasMatch(t) == false) continue;
    await _renderLao(t, 8, false);
    await _renderLao(t, 8, true);
  }
}

pw.Widget _txt(String t,
    {double size = 8, bool bold = false, bool right = false}) {
  final c = _txtCache['${bold ? 1 : 0}|$size|$t'];
  if (c != null) {
    return pw.Align(
      alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: pw.Image(pw.MemoryImage(c.bytes), width: c.w, height: c.h),
    );
  }
  return pw.Text(t,
      textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal));
}

String _s(dynamic m, String k) {
  if (m is Map) {
    final v = m[k];
    return v == null ? '' : '$v';
  }
  return '';
}

double _n(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);

String _day(String v) => v.split('T').first;

String _th(double v) {
  final n = v.round();
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

String _stamp() {
  final t = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}';
}

List<BranchPriceRow> _shown(PriceReportData d) => d.rows
    .where((r) => r.priceBuy != 0 || r.priceSale != 0 || r.total != 0)
    .toList();

// cells: branch, po, grn, date, item, qty, unit, amount
List<_Ln> _poLines(PriceReportData d, Map<String, String> names) {
  final out = <_Ln>[];
  for (final p in d.pos) {
    final gid = _s(p, 'id');
    final bid = _s(p, 'branchId');
    final br = names[bid] ?? bid;
    for (final e in d.items) {
      if (_s(e, 'grnId') != gid) continue;
      out.add(_Ln(<Object>[
        br,
        _s(p, 'poNo'),
        _s(p, 'grnNo'),
        _day(_s(p, 'receiptDate')),
        _s(e, 'name'),
        _n(e['qty']).round(),
        _n(e['unitCost']).roundToDouble(),
        _n(e['amount']).roundToDouble(),
      ], d.imgFor(e, 'name')));
    }
  }
  return out;
}

// cells: branch, atm, po, date, part, qty, unit, amount
List<_Ln> _usedLines(PriceReportData d, Map<String, String> names) {
  final out = <_Ln>[];
  for (final x in d.used) {
    final bid = _s(x, 'branchId');
    final atm = _s(x, 'atmId');
    out.add(_Ln(<Object>[
      names[bid] ?? bid,
      atm.isEmpty ? '-' : atm,
      _s(x, 'poNo'),
      _day(_s(x, 'createdAt')),
      _s(x, 'productName'),
      _n(x['qty']).round(),
      _n(x['unitCost']).roundToDouble(),
      _n(x['amount']).roundToDouble(),
    ], d.imgFor(x, 'productName')));
  }
  return out;
}

Future<void> sharePriceReportXlsx(PriceReportData d) async {
  final names = {for (final r in d.rows) r.branchId: r.branch};
  final po = _poLines(d, names);
  final us = _usedLines(d, names);
  final urls = <String>{
    for (final l in po)
      if (l.url.isNotEmpty) l.url,
    for (final l in us)
      if (l.url.isNotEmpty) l.url,
  };
  final thumbs = await _loadThumbs(urls);

  final rows = <List<Object>>[];
  final bold = <int>{};
  final images = <XlImage>[];
  final heights = <int, double>{};
  void add(List<Object> r, [bool b = false]) {
    if (b) bold.add(rows.length);
    rows.add(r);
  }

  void addLine(_Ln l) {
    final t = thumbs[l.url];
    if (t != null) {
      images.add(XlImage(
          row: rows.length,
          col: 0,
          key: l.url,
          bytes: t.bytes,
          w: t.w,
          h: t.h));
      heights[rows.length] = 40.0;
    }
    add(<Object>['', ...l.cells]);
  }

  final lh = await loadLetterhead();
  const xlW = 1305;
  debugPrint(
      '[XLSX] letterhead ready: header ${lh.hw}x${lh.hh}, footer ${lh.fw}x${lh.fh}, po=${po.length} used=${us.length}');
  images.add(XlImage(
      row: 0,
      col: 0,
      key: 'ldb_header',
      bytes: lh.headerJpg,
      w: xlW,
      h: (xlW * lh.hh / lh.hw).round()));
  for (var i = 0; i < 4; i++) {
    heights[rows.length] = 42.0;
    add(<Object>[]);
  }
  add(<Object>['ລາຍງານລາຄາອາໄຫຼ່ (LAK)'], true);
  add(<Object>['ໄລຍະ', d.range]);
  add(<Object>['ສາຂາ', d.branch]);
  add(<Object>[]);
  add(<Object>['', 'Branch', 'Price buy', 'Used', 'Total'], true);
  double tb = 0;
  double tu = 0;
  double tt = 0;
  for (final r in _shown(d)) {
    tb += r.priceBuy;
    tu += r.priceSale;
    tt += r.total;
    add(<Object>[
      '',
      r.branch,
      r.priceBuy.roundToDouble(),
      r.priceSale.roundToDouble(),
      r.total.roundToDouble()
    ]);
  }
  add(<Object>[
    '',
    'Total',
    tb.roundToDouble(),
    tu.roundToDouble(),
    tt.roundToDouble()
  ], true);

  if (po.isNotEmpty) {
    add(<Object>[]);
    add(<Object>['ຊື້ເຂົ້າ (PO)'], true);
    add(<Object>[
      'Image',
      'Branch',
      'PO',
      'GRN',
      'Date',
      'Item',
      'Qty',
      'Unit LAK',
      'Amount LAK'
    ], true);
    double sum = 0;
    for (final l in po) {
      sum += l.cells[7] as double;
      addLine(l);
    }
    add(<Object>['', '', '', '', '', 'Total', '', '', sum], true);
  }

  if (us.isNotEmpty) {
    add(<Object>[]);
    add(<Object>['ນຳໃຊ້ (ສ້ອມ)'], true);
    add(<Object>[
      'Image',
      'Branch',
      'ATM ID',
      'PO',
      'Date',
      'Part',
      'Qty',
      'Unit LAK',
      'Amount LAK'
    ], true);
    double sum = 0;
    for (final l in us) {
      sum += l.cells[7] as double;
      addLine(l);
    }
    add(<Object>['', '', '', '', '', 'Total', '', '', sum], true);
  }

  add(<Object>[]);
  heights[rows.length] = 28.0;
  add(<Object>[
    '',
    'ຜູ້ຈັດທຳ (Prepared by)',
    '',
    '',
    '',
    'ຜູ້ອະນຸມັດ (Approved by)'
  ], true);
  heights[rows.length] = 54.0;
  add(<Object>[]);
  add(<Object>[
    '',
    '______________________',
    '',
    '',
    '',
    '______________________'
  ]);
  add(<Object>[
    '',
    'ຊື່: ........................',
    '',
    '',
    '',
    'ຊື່: ........................'
  ]);
  add(<Object>[
    '',
    'ວັນທີ: ....../....../..........',
    '',
    '',
    '',
    'ວັນທີ: ....../....../..........'
  ]);
  add(<Object>[]);
  images.add(XlImage(
      row: rows.length,
      col: 0,
      key: 'ldb_footer',
      bytes: lh.footerJpg,
      w: xlW,
      h: (xlW * lh.fh / lh.fw).round()));
  for (var i = 0; i < 3; i++) {
    heights[rows.length] = 40.0;
    add(<Object>[]);
  }
  debugPrint(
      '[XLSX] build done rows=${rows.length} images=${images.length} ldbImages=${images.where((e) => e.key.startsWith('ldb_')).length}');
  await sharePoXlsx(
    fileName: 'PriceReport_${_stamp()}.xlsx',
    rows: rows,
    boldRows: bold,
    widths: [14, 22, 22, 24, 18, 36, 8, 18, 18],
    images: images,
    rowHeights: heights,
  );
}

pw.Widget _cell(String t, {bool bold = false, bool right = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: _txt(t, size: 8, bold: bold, right: right),
    );

pw.Widget _imgCell(Uint8List? b) => pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: b == null
          ? pw.SizedBox(width: 30, height: 30)
          : pw.Image(pw.MemoryImage(b),
              width: 30, height: 30, fit: pw.BoxFit.fill),
    );

pw.Widget _table(List<String> head, List<List<String>> data,
    Map<int, pw.TableColumnWidth> widths, Set<int> right,
    {List<String>? foot, List<Uint8List?>? imgs}) {
  final hasImg = imgs != null;
  final List<Uint8List?> ims = imgs ?? <Uint8List?>[];
  final off = hasImg ? 1 : 0;
  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        for (var i = 0; i < head.length; i++)
          _cell(head[i], bold: true, right: right.contains(i))
      ],
    ),
  ];
  for (var k = 0; k < data.length; k++) {
    final r = data[k];
    rows.add(pw.TableRow(
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        if (hasImg) _imgCell(k < ims.length ? ims[k] : null),
        for (var i = 0; i < r.length; i++)
          _cell(r[i], right: right.contains(i + off))
      ],
    ));
  }
  final f = foot;
  if (f != null) {
    rows.add(pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: [
        for (var i = 0; i < f.length; i++)
          _cell(f[i], bold: true, right: right.contains(i))
      ],
    ));
  }
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
    columnWidths: widths,
    children: rows,
  );
}

pw.Widget _heading(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
      child: _txt(t, size: 12, bold: true),
    );

pw.Widget _sigBox(String lao, String en, String nameLine, String dateLine) =>
    pw.SizedBox(
      width: 200,
      child:
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        _txt(lao, size: 10, bold: true),
        pw.Text(en, style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 46),
        pw.Container(height: 0.7, color: PdfColors.grey700),
        pw.SizedBox(height: 5),
        _txt(nameLine, size: 9),
        pw.SizedBox(height: 4),
        _txt(dateLine, size: 9),
      ]),
    );

Future<void> sharePriceReportPdf(PriceReportData d) async {
  final names = {for (final r in d.rows) r.branchId: r.branch};
  final po = _poLines(d, names);
  final us = _usedLines(d, names);
  final urls = <String>{
    for (final l in po)
      if (l.url.isNotEmpty) l.url,
    for (final l in us)
      if (l.url.isNotEmpty) l.url,
  };
  final thumbs = await _loadThumbs(urls);

  final fBase = await PdfGoogleFonts.notoSansRegular();
  final fBold = await PdfGoogleFonts.notoSansBold();
  final doc =
      pw.Document(theme: pw.ThemeData.withFont(base: fBase, bold: fBold));

  double tb = 0;
  double tu = 0;
  double tt = 0;
  final sumRows = <List<String>>[];
  for (final r in _shown(d)) {
    tb += r.priceBuy;
    tu += r.priceSale;
    tt += r.total;
    sumRows.add([r.branch, _th(r.priceBuy), _th(r.priceSale), _th(r.total)]);
  }

  final poData = <List<String>>[];
  final poImgs = <Uint8List?>[];
  double poSum = 0;
  for (final l in po) {
    final r = l.cells;
    poSum += r[7] as double;
    poImgs.add(thumbs[l.url]?.bytes);
    poData.add([
      '${r[0]}',
      '${r[1]}',
      '${r[3]}',
      '${r[4]}',
      '${r[5]}',
      _th(r[6] as double),
      _th(r[7] as double)
    ]);
  }

  final usData = <List<String>>[];
  final usImgs = <Uint8List?>[];
  double usSum = 0;
  for (final l in us) {
    final r = l.cells;
    usSum += r[7] as double;
    usImgs.add(thumbs[l.url]?.bytes);
    usData.add([
      '${r[0]}',
      '${r[1]}',
      '${r[2]}',
      '${r[3]}',
      '${r[4]}',
      '${r[5]}',
      _th(r[6] as double),
      _th(r[7] as double)
    ]);
  }

  final headLine = 'ໄລຍະ: ${d.range}    ສາຂາ: ${d.branch}';
  final all = <String>{};
  for (final r in sumRows) {
    all.addAll(r);
  }
  for (final r in poData) {
    all.addAll(r);
  }
  for (final r in usData) {
    all.addAll(r);
  }
  await _prepLao(all);
  await _renderLao('ລາຍງານລາຄາອາໄຫຼ່ (LAK)', 16, true);
  await _renderLao('ຊື້ເຂົ້າ (PO)', 12, true);
  await _renderLao('ນຳໃຊ້ (ສ້ອມ)', 12, true);
  await _renderLao(headLine, 9, false);
  await _renderLao('ຜູ້ຈັດທຳ', 10, true);
  await _renderLao('ຜູ້ອະນຸມັດ', 10, true);
  await _renderLao('ຊື່: ..............................', 9, false);
  await _renderLao('ວັນທີ: ......../......../............', 9, false);

  final lineWidths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(34),
    1: const pw.FlexColumnWidth(2),
    2: const pw.FlexColumnWidth(2),
    3: const pw.FlexColumnWidth(2),
    4: const pw.FlexColumnWidth(4),
    5: const pw.FixedColumnWidth(26),
    6: const pw.FlexColumnWidth(2.2),
    7: const pw.FlexColumnWidth(2.4),
  };

  final lh = await loadLetterhead();
  final pageW = PdfPageFormat.a4.width;
  debugPrint(
      '[PDF] page width=$pageW headerH=${(pageW * lh.headerRatio).toStringAsFixed(1)} footerH=${(pageW * lh.footerRatio).toStringAsFixed(1)}');
  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(
          24, pageW * lh.headerRatio + 10, 24, pageW * lh.footerRatio + 8),
      theme: pw.ThemeData.withFont(base: fBase, bold: fBold),
      buildBackground: (ctx) => ldbPdfBackground(lh),
    ),
    build: (ctx) => [
      _txt('ລາຍງານລາຄາອາໄຫຼ່ (LAK)', size: 16, bold: true),
      pw.SizedBox(height: 4),
      _txt(headLine, size: 9),
      pw.SizedBox(height: 10),
      _table(
        ['Branch', 'Price buy', 'Used', 'Total'],
        sumRows,
        {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(2),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FlexColumnWidth(2),
        },
        {1, 2, 3},
        foot: ['Total', _th(tb), _th(tu), _th(tt)],
      ),
      if (poData.isNotEmpty) _heading('ຊື້ເຂົ້າ (PO)'),
      if (poData.isNotEmpty)
        _table(
            [
              '',
              'Branch',
              'PO',
              'Date',
              'Item',
              'Qty',
              'Unit LAK',
              'Amount LAK'
            ],
            poData,
            lineWidths,
            {5, 6, 7},
            imgs: poImgs,
            foot: ['', '', '', '', 'Total', '', '', _th(poSum)]),
      if (usData.isNotEmpty) _heading('ນຳໃຊ້ (ສ້ອມ)'),
      if (usData.isNotEmpty)
        _table(
            [
              '',
              'Branch',
              'ATM ID',
              'PO',
              'Date',
              'Part',
              'Qty',
              'Unit LAK',
              'Amount LAK'
            ],
            usData,
            <int, pw.TableColumnWidth>{
              0: const pw.FixedColumnWidth(34),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2.4),
              4: const pw.FlexColumnWidth(2),
              5: const pw.FlexColumnWidth(3.4),
              6: const pw.FixedColumnWidth(24),
              7: const pw.FlexColumnWidth(2.2),
              8: const pw.FlexColumnWidth(2.4),
            },
            {6, 7, 8},
            imgs: usImgs,
            foot: ['', '', '', '', '', 'Total', '', '', _th(usSum)]),
      pw.SizedBox(height: 28),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 18),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _sigBox(
                  'ຜູ້ຈັດທຳ',
                  'Prepared by',
                  'ຊື່: ..............................',
                  'ວັນທີ: ......../......../............'),
              _sigBox(
                  'ຜູ້ອະນຸມັດ',
                  'Approved by',
                  'ຊື່: ..............................',
                  'ວັນທີ: ......../......../............'),
            ]),
      ),
    ],
  ));

  final bytes = await doc.save();
  debugPrint('[PDF] saved bytes=${bytes.length}');
  await Printing.sharePdf(
      bytes: bytes, filename: 'PriceReport_${_stamp()}.pdf');
}

/// PDF of one stock transfer: letterhead, header info, item table, signatures.
Future<void> shareTransferPdf(
    Map<String, dynamic> t, Map<String, String> imageUrls) async {
  String g(dynamic m, List<String> keys) {
    for (final k in keys) {
      final v = m is Map ? m[k] : null;
      if (v != null && '$v'.isNotEmpty) return '$v';
    }
    return '';
  }

  final no = g(t, ['transferNo', 'id']);
  final from = g(t, ['fromName', 'fromBranchName', 'fromBranchId']);
  final to = g(t, ['toName', 'toBranchName', 'toBranchId']);
  final sent = g(t, ['sentAt']);
  final date = sent.length >= 10 ? sent.substring(0, 10) : sent;
  final items = t['items'] is List
      ? [for (final e in t['items'] as List) e as Map]
      : <Map>[];

  final urls = <String>{
    for (final i in items)
      if ((imageUrls['${i['productId']}'] ?? '').isNotEmpty)
        imageUrls['${i['productId']}']!
  };
  final thumbs = await _loadThumbs(urls);

  double total = 0;
  final data = <List<String>>[];
  final imgs = <Uint8List?>[];
  var n = 0;
  for (final i in items) {
    n++;
    final q = double.tryParse('${i['qty'] ?? i['quantity'] ?? 0}') ?? 0;
    total += q;
    imgs.add(thumbs[imageUrls['${i['productId']}'] ?? '']?.bytes);
    data.add([
      '$n',
      g(i, ['productName', 'name', 'productId']),
      g(i, ['poNo']),
      q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2),
    ]);
  }

  final texts = <String>{
    'ໃບໂອນອາໄຫຼ່',
    'ເລກທີ',
    'ວັນທີ',
    'ຈາກສາຂາ',
    'ໄປສາຂາ',
    'ລາຍການ',
    'ສິນຄ້າ',
    'ຈຳນວນ',
    'ລວມ',
    'ຜູ້ສົ່ງ',
    'ຜູ້ຮັບ',
    'ວັນທີ / Date',
    'ລາຍເຊັນ',
    'ເລກທີ: ',
    'ວັນທີ: ',
    'ຈາກສາຂາ: ',
    'ໄປສາຂາ: ',
    no,
    from,
    to,
    date,
    for (final r in data) ...r,
  };
  await _prepLao(texts);
  for (final sz in [16.0, 9.0, 12.0]) {
    for (final tx in texts) {
      if (_laoRe.hasMatch(tx)) {
        await _renderLao(tx, sz, true);
        await _renderLao(tx, sz, false);
      }
    }
  }

  final fBase = await PdfGoogleFonts.notoSansRegular();
  final fBold = await PdfGoogleFonts.notoSansBold();
  final doc =
      pw.Document(theme: pw.ThemeData.withFont(base: fBase, bold: fBold));
  final lh = await loadLetterhead();
  final pageW = PdfPageFormat.a4.width;

  pw.Widget sign(String role) => pw.Expanded(
          child: pw.Column(children: [
        _txt(role, size: 9, bold: true),
        pw.SizedBox(height: 44),
        pw.Container(height: 0.6, color: PdfColors.grey700),
        pw.SizedBox(height: 3),
        _txt('ລາຍເຊັນ', size: 9),
        pw.SizedBox(height: 6),
        _txt('ວັນທີ / Date', size: 9),
      ]));

  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(
          24, pageW * lh.headerRatio + 10, 24, pageW * lh.footerRatio + 8),
      theme: pw.ThemeData.withFont(base: fBase, bold: fBold),
      buildBackground: (ctx) => ldbPdfBackground(lh),
    ),
    build: (ctx) => [
      _txt('ໃບໂອນອາໄຫຼ່', size: 16, bold: true),
      pw.SizedBox(height: 6),
      pw.Row(children: [
        _txt('ເລກທີ: ', size: 9, bold: true),
        _txt(no, size: 9),
        pw.SizedBox(width: 24),
        _txt('ວັນທີ: ', size: 9, bold: true),
        _txt(date, size: 9),
      ]),
      pw.SizedBox(height: 3),
      pw.Row(children: [
        _txt('ຈາກສາຂາ: ', size: 9, bold: true),
        _txt(from, size: 9),
        pw.SizedBox(width: 24),
        _txt('ໄປສາຂາ: ', size: 9, bold: true),
        _txt(to, size: 9),
      ]),
      pw.SizedBox(height: 10),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
        columnWidths: {
          0: const pw.FixedColumnWidth(26),
          1: const pw.FixedColumnWidth(68),
          2: const pw.FlexColumnWidth(5),
          3: const pw.FlexColumnWidth(2.6),
          4: const pw.FixedColumnWidth(48),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              _cell('No', bold: true),
              _cell('', bold: true),
              _cell('ສິນຄ້າ', bold: true),
              _cell('PO', bold: true),
              _cell('ຈຳນວນ', bold: true, right: true),
            ],
          ),
          for (var k = 0; k < data.length; k++)
            pw.TableRow(
              verticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                _cell(data[k][0]),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: imgs[k] == null
                      ? pw.SizedBox(width: 60, height: 60)
                      : pw.Image(pw.MemoryImage(imgs[k]!),
                          width: 60, height: 60, fit: pw.BoxFit.cover),
                ),
                _cell(data[k][1]),
                _cell(data[k][2]),
                _cell(data[k][3], right: true),
              ],
            ),
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
            children: [
              _cell(''),
              _cell(''),
              _cell('ລວມ', bold: true),
              _cell(''),
              _cell(
                  total == total.roundToDouble()
                      ? total.toInt().toString()
                      : total.toStringAsFixed(2),
                  bold: true,
                  right: true),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 40),
      pw.Row(
          children: [sign('ຜູ້ສົ່ງ'), pw.SizedBox(width: 40), sign('ຜູ້ຮັບ')]),
    ],
  ));

  final bytes = await doc.save();
  await Printing.sharePdf(
      bytes: bytes, filename: 'Transfer_${no.isEmpty ? _stamp() : no}.pdf');
}

// ---- withdrawal letter: Lao paragraphs with automatic line wrapping ----

String _wdKey(String t, double size, bool bold, double width) =>
    'B|${bold ? 1 : 0}|$size|${width.toStringAsFixed(1)}|$t';

Future<void> _wdRenderBlock(
    String t, double size, bool bold, double width) async {
  final key = _wdKey(t, size, bold, width);
  if (_txtCache.containsKey(key)) return;
  await _ensureFont();
  final tp = TextPainter(
    text: TextSpan(
        text: t,
        style: TextStyle(
            fontFamily: bold ? 'PhetsarathRepBold' : 'PhetsarathRep',
            fontSize: size * _sc,
            height: 1.45,
            color: const ui.Color(0xFF000000))),
    textDirection: TextDirection.ltr,
  );
  tp.layout(maxWidth: width * _sc);
  final w = tp.width.ceil() + 2;
  final h = tp.height.ceil() + 2;
  final rec = ui.PictureRecorder();
  final cv = ui.Canvas(rec);
  tp.paint(cv, const ui.Offset(1, 1));
  final im = await rec.endRecording().toImage(w, h);
  final bd = await im.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) return;
  _txtCache[key] =
      _TxtImg(bd.buffer.asUint8List(), w.toDouble() / _sc, h.toDouble() / _sc);
}

Future<void> _wdPrep(String t, double size, bool bold, double width) async {
  if (t.isEmpty || !_laoRe.hasMatch(t)) return;
  await _wdRenderBlock(t, size, bold, width);
}

pw.Widget _wdBlock(String t, double size, bool bold, double width,
    {pw.Alignment align = pw.Alignment.topLeft,
    pw.TextAlign ta = pw.TextAlign.left}) {
  final c = _txtCache[_wdKey(t, size, bold, width)];
  final child = c == null
      ? pw.Text(t,
          textAlign: ta,
          style: pw.TextStyle(
              fontSize: size,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))
      : pw.Image(pw.MemoryImage(c.bytes), width: c.w, height: c.h);
  return pw.Align(alignment: align, child: child);
}

pw.Widget _wdCell(String t, double colW, {bool bold = false}) {
  final inner = colW - 8;
  return pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: _laoRe.hasMatch(t)
        ? _wdBlock(t, 9, bold, inner,
            align: pw.Alignment.topCenter, ta: pw.TextAlign.center)
        : pw.Center(
            child: pw.Text(t.isEmpty ? '-' : t,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
  );
}

/// PDF of one withdrawal bill as a formal letter (ໜັງສືສະເໜີ): LDB letterhead as the
/// page background, header lines, request text, table, closing, two signatures.
/// [w] = a row of GET /withdrawals, optionally with atmBranch / atmModel / atmLocation.
/// [imageUrls]: productId -> full image url.
Future<Uint8List> buildWithdrawalPdf(
    Map<String, dynamic> w, Map<String, String> imageUrls) async {
  String g(dynamic m, List<String> keys) {
    for (final k in keys) {
      final v = m is Map ? m[k] : null;
      if (v != null && '$v'.isNotEmpty) return '$v';
    }
    return '';
  }

  const months = [
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
  String laoDate(String s) {
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    final l = d.toLocal();
    return '${l.day} ${months[l.month - 1]} ${l.year}';
  }

  final date = laoDate(g(w, ['createdAt']));
  var branch = g(w, ['atmBranch']);
  if (branch.isEmpty) branch = g(w, ['branchName', 'branchId']);
  final model = g(w, ['atmModel']);
  final location = g(w, ['atmLocation']);
  final items = w['items'] is List
      ? [for (final e in w['items'] as List) e as Map]
      : <Map>[];

  final urls = <String>{
    for (final i in items)
      if ((imageUrls['${i['productId']}'] ?? '').isNotEmpty)
        imageUrls['${i['productId']}']!
  };
  final thumbs = await _loadThumbs(urls);

  // ---- fixed wording of the letter (edit here if a word is wrong) ----
  const title = 'ໜັງສືສະເໜີ';
  const toLine = 'ຮຽນ: ທ່ານ ຫົວໜ້າຝ່າຍເຕັກໂນໂລຊີຂໍ້ມູນຂ່າວສານທີ່ນັບຖືຢ່າງສູງ';
  const subjectLine = 'ເລື່ອງ: ເບີກອາໄຫຼ່ເອທີເອັມ ATM';
  final refLine = '- ອີງຕາມ ການກວດກາຕິດຕາມຕູ້ ATM ຄືຈິງໃນຄັ້ງວັນທີ່ $date.';
  final bodyText =
      '          ສາຂາ $branch ຂໍຖືເປັນກຽດສະເໜີມາຍັງທ່ານເພື່ອເບີກອາໄຫຼ່ເອທີເອັມເນື່ອງຈາກອຸປະກອນຂອງຕູ້ໃຊ້ງານບໍ່ໄດ້ ເຊິ່ງລາຍລະອຽດດັ່ງລຸ່ມນີ້:';
  const closeText =
      '          ດັ່ງນັ້ນ ຈຶ່ງສະເໜີມາຍັງທ່ານເພື່ອພິຈາລະນາ ແລະ ແກ້ໄຂຕາມຄວາມເໝາະສົມດ້ວຍ.';
  const respectText = 'ຮຽນມາດ້ວຍຄວາມເຄົາລົບ ແລະ ນັບຖືຢ່າງສູງ.';
  final topLeft = 'ສາຂາ $branch';
  const topNo = 'ເລກທີ່: ................................';
  final topPlace = '$branch, ວັນທີ $date';
  final signLeft = 'ຫົວໜ້າສາຂາ $branch';
  const signRight = 'ຜູ້ສະເໜີ';

  final pageW = PdfPageFormat.a4.width;
  const margin = 36.0;
  final contentW = pageW - margin * 2;
  const half = 250.0;
  final cols = <double>[28, 84, 76, 98, 120, 40, 77];
  const heads = [
    'ລຳດັບ',
    'ສາຂາ',
    'ລຸ້ນຕູ້',
    'ທີ່ຕັ້ງຕູ້',
    'ອາໄຫຼ່',
    'ຈຳນວນ',
    'ວັນເດືອນປີ'
  ];

  final rowsData = <List<String>>[];
  final imgs = <Uint8List?>[];
  var n = 0;
  for (final i in items) {
    n++;
    final q = double.tryParse('${i['qty'] ?? 0}') ?? 0;
    imgs.add(thumbs[imageUrls['${i['productId']}'] ?? '']?.bytes);
    rowsData.add([
      '$n',
      branch,
      model,
      location,
      g(i, ['productName', 'name', 'productId']),
      q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2),
      date,
    ]);
  }

  await _ensureFont();
  await _wdPrep(title, 18, true, contentW);
  await _wdPrep(toLine, 11, false, contentW);
  await _wdPrep(subjectLine, 11, false, contentW);
  await _wdPrep(refLine, 11, false, contentW);
  await _wdPrep(bodyText, 11, false, contentW);
  await _wdPrep(closeText, 11, false, contentW);
  await _wdPrep(respectText, 11, false, contentW);
  await _wdPrep(topLeft, 11, false, half);
  await _wdPrep(topNo, 11, false, half);
  await _wdPrep(topPlace, 11, false, half);
  await _wdPrep(signLeft, 11, true, 240);
  await _wdPrep(signRight, 11, true, 240);
  for (var c = 0; c < heads.length; c++) {
    await _wdPrep(heads[c], 9, true, cols[c] - 8);
  }
  for (final r in rowsData) {
    for (var c = 0; c < r.length; c++) {
      await _wdPrep(r[c], 9, false, cols[c] - 8);
    }
  }

  final fBase = await PdfGoogleFonts.notoSansRegular();
  final fBold = await PdfGoogleFonts.notoSansBold();
  final doc =
      pw.Document(theme: pw.ThemeData.withFont(base: fBase, bold: fBold));
  final lh = await loadLetterhead();

  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(margin, pageW * lh.headerRatio + 10,
          margin, pageW * lh.footerRatio + 8),
      theme: pw.ThemeData.withFont(base: fBase, bold: fBold),
      buildBackground: (ctx) => ldbPdfBackground(lh),
    ),
    build: (ctx) => [
      pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.SizedBox(width: half, child: _wdBlock(topLeft, 11, false, half)),
            pw.SizedBox(
                width: half,
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _wdBlock(topNo, 11, false, half,
                          align: pw.Alignment.topRight,
                          ta: pw.TextAlign.right),
                      _wdBlock(topPlace, 11, false, half,
                          align: pw.Alignment.topRight,
                          ta: pw.TextAlign.right),
                    ])),
          ]),
      pw.SizedBox(height: 16),
      _wdBlock(title, 18, true, contentW,
          align: pw.Alignment.topCenter, ta: pw.TextAlign.center),
      pw.SizedBox(height: 12),
      _wdBlock(toLine, 11, false, contentW),
      _wdBlock(subjectLine, 11, false, contentW),
      _wdBlock(refLine, 11, false, contentW),
      pw.SizedBox(height: 8),
      _wdBlock(bodyText, 11, false, contentW),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
        columnWidths: {
          for (var c = 0; c < cols.length; c++)
            c: pw.FixedColumnWidth(cols[c])
        },
        children: [
          pw.TableRow(children: [
            for (var c = 0; c < heads.length; c++)
              _wdCell(heads[c], cols[c], bold: true),
          ]),
          for (var k = 0; k < rowsData.length; k++)
            pw.TableRow(
              verticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                for (var c = 0; c < rowsData[k].length; c++)
                  c == 4
                      ? pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
                          if (imgs[k] != null)
                            pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 4),
                                child: pw.Image(pw.MemoryImage(imgs[k]!),
                                    width: 40,
                                    height: 40,
                                    fit: pw.BoxFit.cover)),
                          _wdCell(rowsData[k][c], cols[c]),
                        ])
                      : _wdCell(rowsData[k][c], cols[c]),
              ],
            ),
        ],
      ),
      pw.SizedBox(height: 12),
      _wdBlock(closeText, 11, false, contentW),
      _wdBlock(respectText, 11, false, contentW,
          align: pw.Alignment.topRight, ta: pw.TextAlign.right),
      pw.SizedBox(height: 26),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
            child: pw.Column(children: [
          _wdBlock(signLeft, 11, true, 240,
              align: pw.Alignment.topCenter, ta: pw.TextAlign.center),
          pw.SizedBox(height: 100),
        ])),
        pw.Expanded(
            child: pw.Column(children: [
          _wdBlock(signRight, 11, true, 240,
              align: pw.Alignment.topCenter, ta: pw.TextAlign.center),
          pw.SizedBox(height: 100),
        ])),
      ]),
    ],
  ));

  return doc.save();
}
