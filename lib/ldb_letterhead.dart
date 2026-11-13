import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextDirection;
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'ldb_address.dart';

class LdbLetterhead {
  final Uint8List headerPng;
  final Uint8List headerJpg;
  final Uint8List footerPng;
  final Uint8List footerJpg;
  final int hw;
  final int hh;
  final int fw;
  final int fh;
  const LdbLetterhead({
    required this.headerPng,
    required this.headerJpg,
    required this.footerPng,
    required this.footerJpg,
    required this.hw,
    required this.hh,
    required this.fw,
    required this.fh,
  });
  double get headerRatio => hh / hw;
  double get footerRatio => fh / fw;
}

LdbLetterhead? _cache;
bool _fontOk = false;

Future<Uint8List?> _addrPng(String lao, String en) async {
  if (_fontOk == false) {
    final fl = FontLoader('LdbLao')
      ..addFont(rootBundle.load('assets/fonts/Phetsarath-OT-Bold.ttf'));
    await fl.load();
    _fontOk = true;
  }
  const sc = 3.0;
  const white = ui.Color(0xFFFFFFFF);
  final ps = <TextPainter>[];
  if (lao.isNotEmpty) {
    ps.add(TextPainter(
        text: TextSpan(
            text: lao,
            style: const TextStyle(
                fontFamily: 'LdbLao', fontSize: 21 * sc, color: white)),
        textDirection: TextDirection.ltr)
      ..layout());
  }
  if (en.isNotEmpty) {
    ps.add(TextPainter(
        text: TextSpan(
            text: en,
            style: const TextStyle(
                fontFamily: 'serif',
                fontWeight: ui.FontWeight.bold,
                fontSize: 19 * sc,
                color: white)),
        textDirection: TextDirection.ltr)
      ..layout());
  }
  if (ps.isEmpty) return null;
  double w = 0;
  double h = 0;
  for (final p in ps) {
    w = math.max(w, p.width);
    h += p.height;
  }
  final wi = w.ceil() + 8;
  final hi = h.ceil() + 8;
  final rec = ui.PictureRecorder();
  final cv = ui.Canvas(rec);
  var y = 4.0;
  for (final p in ps) {
    p.paint(cv, ui.Offset((wi - p.width) / 2, y));
    y += p.height;
  }
  final im = await rec.endRecording().toImage(wi, hi);
  final bd = await im.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) return null;
  return bd.buffer.asUint8List();
}

Future<LdbLetterhead> loadLetterhead() async {
  final c = _cache;
  debugPrint('[LH] loadLetterhead cached=${c != null}');
  if (c != null) return c;
  final hb =
      (await rootBundle.load('assets/ldb/ldb_header.png')).buffer.asUint8List();
  final fb =
      (await rootBundle.load('assets/ldb/ldb_footer.png')).buffer.asUint8List();
  final hImg = img.decodePng(hb);
  final fImg = img.decodePng(fb);
  debugPrint(
      '[LH] header bytes=${hb.length} decoded=${hImg == null ? 'NULL' : '${hImg.width}x${hImg.height}'}');
  debugPrint(
      '[LH] footer bytes=${fb.length} decoded=${fImg == null ? 'NULL' : '${fImg.width}x${fImg.height}'}');
  if (hImg == null || fImg == null) {
    throw Exception('Cannot read assets/ldb images');
  }
  final a = await _addrPng(ldbAddressLao, ldbAddressEn);
  debugPrint(
      '[LH] address lao=${ldbAddressLao.length} chars en=${ldbAddressEn.length} chars textPng=${a == null ? 'none' : a.length}');
  if (a != null) {
    final t = img.decodePng(a);
    if (t != null) {
      const sc = 3.0;
      final tw = t.width / sc;
      final th = t.height / sc;
      final f = math.min(1.0, 1240.0 / tw);
      final small = img.copyResize(t,
          width: (tw * f).round(),
          height: (th * f).round(),
          interpolation: img.Interpolation.average);
      final x = (700 - small.width / 2).round();
      final y = (133 - small.height / 2).round();
      img.compositeImage(fImg, small, dstX: x, dstY: y);
    }
  }
  final r = LdbLetterhead(
    headerPng: hb,
    headerJpg: Uint8List.fromList(img.encodeJpg(hImg, quality: 92)),
    footerPng: Uint8List.fromList(img.encodePng(fImg)),
    footerJpg: Uint8List.fromList(img.encodeJpg(fImg, quality: 92)),
    hw: hImg.width,
    hh: hImg.height,
    fw: fImg.width,
    fh: fImg.height,
  );
  debugPrint(
      '[LH] ready header ${r.hw}x${r.hh} footer ${r.fw}x${r.fh} headerJpg=${r.headerJpg.length} footerJpg=${r.footerJpg.length}');
  _cache = r;
  return r;
}

pw.Widget ldbPdfBackground(LdbLetterhead l, {bool showFooter = true}) {
  final w = PdfPageFormat.a4.width;
  return pw.FullPage(
    ignoreMargins: true,
    child: pw.Stack(children: [
      pw.Positioned(
          left: 0,
          top: 0,
          child: pw.Image(pw.MemoryImage(l.headerPng),
              width: w, height: w * l.headerRatio, fit: pw.BoxFit.fill)),
      if (showFooter)
        pw.Positioned(
            left: 0,
            bottom: 0,
            child: pw.Image(pw.MemoryImage(l.footerPng),
                width: w, height: w * l.footerRatio, fit: pw.BoxFit.fill)),
    ]),
  );
}
