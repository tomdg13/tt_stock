// Search products by photo: compares colour + layout of the photo with the product images.
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'api.dart';
import 'product_images.dart';

List<double>? _photoFeature(Uint8List bytes) {
  final src = img.decodeImage(bytes);
  if (src == null) return null;
  final s = img.copyResize(src, width: 24, height: 24);
  final hist = List<double>.filled(64, 0);
  final grid = List<double>.filled(48, 0);
  final cnt = List<int>.filled(16, 0);
  for (var y = 0; y < 24; y++) {
    for (var x = 0; x < 24; x++) {
      final p = s.getPixel(x, y);
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      hist[(r ~/ 64) * 16 + (g ~/ 64) * 4 + (b ~/ 64)] += 1;
      final c = (y ~/ 6) * 4 + (x ~/ 6);
      grid[c * 3] += r / 255;
      grid[c * 3 + 1] += g / 255;
      grid[c * 3 + 2] += b / 255;
      cnt[c]++;
    }
  }
  for (var i = 0; i < 64; i++) {
    hist[i] /= 576;
  }
  for (var i = 0; i < 48; i++) {
    grid[i] /= cnt[i ~/ 3];
  }
  return [...hist, ...grid];
}

double _photoSim(List<double> a, List<double> b) {
  var h = 0.0, g = 0.0;
  for (var i = 0; i < 64; i++) {
    h += (a[i] - b[i]).abs();
  }
  for (var i = 64; i < 112; i++) {
    g += (a[i] - b[i]).abs();
  }
  return 1 - (0.5 * (h / 2) + 0.5 * (g / 48));
}

final _featCache = <String, List<double>>{};

/// imgs = { productId: imagePath }. Returns productIds sorted by similarity (best first).
Future<List<MapEntry<String, double>>> matchProductPhoto(
    Uint8List photo, Map<String, String> imgs) async {
  final q = await compute(_photoFeature, photo);
  if (q == null) return [];
  final ids = imgs.keys.where((k) => imgs[k]!.isNotEmpty).toList();
  final out = <MapEntry<String, double>>[];
  for (var i = 0; i < ids.length; i += 8) {
    await Future.wait(ids.skip(i).take(8).map((id) async {
      final url = productImageUrl(imgs[id]!);
      var f = _featCache[url];
      if (f == null) {
        try {
          final res = await http
              .get(Uri.parse(url),
                  headers: Api.token == null
                      ? <String, String>{}
                      : {'Authorization': 'Bearer ${Api.token}'})
              .timeout(const Duration(seconds: 15));
          if (res.statusCode == 200) {
            f = await compute(_photoFeature, res.bodyBytes);
            if (f != null) _featCache[url] = f;
          }
        } catch (_) {}
      }
      if (f != null) out.add(MapEntry(id, _photoSim(q, f)));
    }));
  }
  out.sort((a, b) => b.value.compareTo(a.value));
  return out;
}
