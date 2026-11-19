import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextDirection;
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'api.dart';
import 'product_images.dart' show productImageUrl;
import 'widgets.dart';

const double _k = 3.0;

class _Ti {
  final Uint8List bytes;
  final double w;
  final double h;
  const _Ti(this.bytes, this.w, this.h);
}

final Map<String, _Ti> _cache = {};
bool _fontOk = false;

Future<void> _font() async {
  if (_fontOk) return;
  final a = FontLoader('PhetsarathPlan')
    ..addFont(rootBundle.load('assets/fonts/Phetsarath-OT.ttf'));
  await a.load();
  final b = FontLoader('PhetsarathPlanBold')
    ..addFont(rootBundle.load('assets/fonts/Phetsarath-OT-Bold.ttf'));
  await b.load();
  _fontOk = true;
}

Future<_Ti?> _render(String t, double size, bool bold, double maxW) async {
  final tp = TextPainter(
    text: TextSpan(
        text: t,
        style: TextStyle(
            fontFamily: bold ? 'PhetsarathPlanBold' : 'PhetsarathPlan',
            fontSize: size * _k,
            color: const ui.Color(0xFF000000))),
    textDirection: TextDirection.ltr,
  );
  if (maxW > 0) {
    tp.layout(maxWidth: maxW * _k);
  } else {
    tp.layout();
  }
  final w = tp.width.ceil() + 2;
  final h = tp.height.ceil() + 2;
  final rec = ui.PictureRecorder();
  final cv = ui.Canvas(rec);
  tp.paint(cv, const ui.Offset(1, 1));
  final im = await rec.endRecording().toImage(w, h);
  final bd = await im.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) return null;
  return _Ti(bd.buffer.asUint8List(), w.toDouble() / _k, h.toDouble() / _k);
}

Future<pw.Widget> _t(String t,
    {double size = 8,
    bool bold = false,
    bool right = false,
    double maxW = 0}) async {
  if (t.isEmpty) return pw.SizedBox(height: size + 2);
  final key = '${bold ? 1 : 0}|$size|$maxW|$t';
  final c = _cache[key] ?? await _render(t, size, bold, maxW);
  if (c == null) {
    return pw.Text(t, style: pw.TextStyle(fontSize: size));
  }
  _cache[key] = c;
  return pw.Align(
    alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
    child: pw.Image(pw.MemoryImage(c.bytes), width: c.w, height: c.h),
  );
}

Future<pw.Widget> _c(String t,
    {bool bold = false, bool right = false, double maxW = 0}) async {
  final w = await _t(t, bold: bold, right: right, maxW: maxW);
  return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: w);
}

pw.Widget _imgCell(Uint8List? b) => pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: b == null
          ? pw.SizedBox(width: 30, height: 30)
          : pw.Image(pw.MemoryImage(b),
              width: 30, height: 30, fit: pw.BoxFit.fill),
    );

List<Object>? _makeThumb(Uint8List b) {
  final im = img.decodeImage(b);
  if (im == null) return null;
  final sq = img.copyResizeCropSquare(im, size: 96);
  final jpg = Uint8List.fromList(img.encodeJpg(sq, quality: 78));
  return <Object>[jpg];
}

Future<Map<String, Uint8List>> _loadThumbs(Set<String> urls) async {
  final out = <String, Uint8List>{};
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
          out[u] = r[0] as Uint8List;
        }
      }
    } catch (e) {
      debugPrint('[PLANPDF] image failed $u: $e');
    }
  }));
  return out;
}

String _q(num v) => v % 1 == 0 ? '${v.toInt()}' : '$v';

String _two(int n) => n < 10 ? '0$n' : '$n';

Future<void> exportPlanPdf(
    Map<String, dynamic> plan, List<Map<String, dynamic>> items) async {
  await _font();
  final rows = items.where((x) => x['done'] == true).toList();
  rows.sort((a, b) {
    final c = '${a['brand'] ?? ''}'.compareTo('${b['brand'] ?? ''}');
    if (c == 0) return '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
    return c;
  });

  final urls = <String>{};
  for (final it in rows) {
    final u = productImageUrl('${it['imageUrl'] ?? ''}');
    if (u.isNotEmpty) urls.add(u);
  }
  final thumbs = await _loadThumbs(urls);
  debugPrint('[PLANPDF] images ${thumbs.length}/${urls.length}');

  final widths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(22),
    1: const pw.FixedColumnWidth(36),
    2: const pw.FlexColumnWidth(1),
    3: const pw.FixedColumnWidth(52),
    4: const pw.FixedColumnWidth(36),
    5: const pw.FixedColumnWidth(60),
    6: const pw.FixedColumnWidth(70),
    7: const pw.FixedColumnWidth(60),
  };

  final trs = <pw.TableRow>[];
  trs.add(pw.TableRow(
    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
    children: [
      await _c('#', bold: true),
      await _c('ຮູບ', bold: true),
      await _c('ສິນຄ້າ', bold: true),
      await _c('ຕ້ອງຊື້', bold: true, right: true),
      await _c('ໜ່ວຍ', bold: true),
      await _c('ຊື້ແຜນນີ້', bold: true, right: true),
      await _c('brand', bold: true),
      await _c('ທີ່ເກັບ', bold: true),
    ],
  ));

  var sumMust = 0.0;
  var sumBuy = 0.0;
  for (var i = 0; i < rows.length; i++) {
    final x = rows[i];
    final u = productImageUrl('${x['imageUrl'] ?? ''}');
    final must = x['must'] ?? x['qty'];
    final m = num0(must).toDouble();
    sumMust += m;
    var buy = '-';
    if (x['buyQty'] is num) {
      final b = num0(x['buyQty']).toDouble();
      sumBuy += b;
      buy = _q(b);
    }
    trs.add(pw.TableRow(
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        await _c('${i + 1}'),
        _imgCell(thumbs[u]),
        await _c('${x['name'] ?? ''}', maxW: 440),
        await _c(_q(m), bold: true, right: true),
        await _c('${x['unit'] ?? ''}'),
        await _c(buy, bold: true, right: true),
        await _c('${x['brand'] ?? ''}'),
        await _c('${x['bin'] ?? ''}'),
      ],
    ));
  }

  trs.add(pw.TableRow(
    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
    children: [
      await _c(''),
      await _c(''),
      await _c('ລວມ ${rows.length} ລາຍການ', bold: true),
      await _c(_q(sumMust), bold: true, right: true),
      await _c(''),
      await _c(_q(sumBuy), bold: true, right: true),
      await _c(''),
      await _c(''),
    ],
  ));

  final created = '${plan['createdAt'] ?? ''}';
  final note = '${plan['note'] ?? ''}';
  final n = DateTime.now();
  final dateTxt = created.length >= 10
      ? created.substring(0, 10)
      : '${n.year}-${_two(n.month)}-${_two(n.day)}';

  final head = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    await _t('${plan['name'] ?? ''}', size: 14, bold: true),
    pw.SizedBox(height: 3),
    if (note.isNotEmpty) await _t('ໝາຍເຫດ: $note', size: 9),
    await _t('ວັນທີ: $dateTxt', size: 9),
    pw.SizedBox(height: 8),
  ]);

  final table = pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
    columnWidths: widths,
    children: trs,
  );

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(24),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8)),
    ),
    build: (ctx) => [head, table],
  ));

  final bytes = await doc.save();
  await Printing.sharePdf(
      bytes: bytes,
      filename: 'buyplan_${n.year}${_two(n.month)}${_two(n.day)}.pdf');
}
