import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colors taken from the TT Stock demo (light and dark).
class Pal {
  final Color bg,
      card,
      tx,
      mut,
      bd,
      pri,
      prit,
      soft,
      warn,
      warnbg,
      bad,
      badbg,
      ok,
      okbg,
      bar;
  const Pal({
    required this.bg,
    required this.card,
    required this.tx,
    required this.mut,
    required this.bd,
    required this.pri,
    required this.prit,
    required this.soft,
    required this.warn,
    required this.warnbg,
    required this.bad,
    required this.badbg,
    required this.ok,
    required this.okbg,
    required this.bar,
  });

  static const light = Pal(
    bg: Color(0xFFEEF1F4),
    card: Color(0xFFFFFFFF),
    tx: Color(0xFF18222B),
    mut: Color(0xFF64707C),
    bd: Color(0xFFDDE2E8),
    pri: Color(0xFF0B6E68),
    prit: Color(0xFFFFFFFF),
    soft: Color(0xFFE3F1EF),
    warn: Color(0xFF9A5A00),
    warnbg: Color(0xFFFDF0D5),
    bad: Color(0xFFB3261E),
    badbg: Color(0xFFFBE4E2),
    ok: Color(0xFF1B6B3A),
    okbg: Color(0xFFDCF2E3),
    bar: Color(0xFF2A9D8F),
  );
  static const dark = Pal(
    bg: Color(0xFF12181D),
    card: Color(0xFF1B242B),
    tx: Color(0xFFE6ECF1),
    mut: Color(0xFF92A0AD),
    bd: Color(0xFF2C3943),
    pri: Color(0xFF3FB8AD),
    prit: Color(0xFF06201E),
    soft: Color(0xFF1D3735),
    warn: Color(0xFFF1B955),
    warnbg: Color(0xFF3A2D12),
    bad: Color(0xFFF28B82),
    badbg: Color(0xFF3B1C1A),
    ok: Color(0xFF7AD39A),
    okbg: Color(0xFF17321F),
    bar: Color(0xFF3FB8AD),
  );
}

Pal pal(BuildContext c) =>
    Theme.of(c).brightness == Brightness.dark ? Pal.dark : Pal.light;

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Pal.dark : Pal.light;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: p.pri, brightness: b).copyWith(
      primary: p.pri,
      onPrimary: p.prit,
      surface: p.card,
      onSurface: p.tx,
      error: p.bad,
      outline: p.bd,
    ),
  );
  OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    textTheme: GoogleFonts.notoSansLaoTextTheme(base.textTheme)
        .apply(bodyColor: p.tx, displayColor: p.tx),
    appBarTheme: AppBarTheme(
      backgroundColor: p.card,
      foregroundColor: p.tx,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: p.bd)),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: p.card),
    dividerColor: p.bd,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.bg,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: ob(p.bd),
      enabledBorder: ob(p.bd),
      focusedBorder: ob(p.pri, 2),
      labelStyle: TextStyle(color: p.mut, fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.pri,
        foregroundColor: p.prit,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.tx,
        side: BorderSide(color: p.bd),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}

/// Pill badge (.badge in the demo). kind: '' | 'in' | 'out' | 'tr'
class Tag extends StatelessWidget {
  final String text, kind;
  const Tag(this.text, [this.kind = '', Key? key]) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    Color bg = p.soft, fg = p.pri;
    if (kind == 'in') {
      bg = p.okbg;
      fg = p.ok;
    } else if (kind == 'out') {
      bg = p.badbg;
      fg = p.bad;
    } else if (kind == 'tr') {
      bg = p.warnbg;
      fg = p.warn;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(fontSize: 12, color: fg)),
    );
  }
}

/// Guess a badge color from a status text.
String kindOf(String v) {
  final s = v.toLowerCase();
  const good = [
    'active',
    'in use',
    'ready',
    'done',
    'received',
    'ok',
    'true',
    '1'
  ];
  const bad = [
    'close',
    'cancel',
    'unactive',
    'inactive',
    'short',
    'none',
    'false',
    '0'
  ];
  const mid = [
    'transit',
    'draft',
    'order',
    'partial',
    'ma',
    'test',
    'move',
    'wait',
    'warehouse',
    'over'
  ];
  if (good.contains(s)) return 'in';
  if (bad.contains(s)) return 'out';
  if (mid.any((m) => s.contains(m))) return 'tr';
  return '';
}

/// Bordered rounded surface. Uses Material (not a colored Container) so that
/// ListTile / Switch / Checkbox inside it can paint their ink effects.
Widget cardBox(BuildContext c,
    {required Widget child,
    Color? color,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
    double radius = 10}) {
  final p = pal(c);
  return Padding(
    padding: margin,
    child: Material(
      color: color ?? p.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: p.bd),
      ),
      child: child,
    ),
  );
}

/// White bordered card with an optional heading (.card in the demo).
class AppCard extends StatelessWidget {
  final String? title;
  final Widget child;
  const AppCard({super.key, this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return cardBox(
      context,
      margin: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(title!,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            child,
          ]),
        ),
      ),
    );
  }
}

/// Number tile (.kpi in the demo).
class Kpi extends StatelessWidget {
  final String value, label;
  final bool warn;
  const Kpi(this.value, this.label, {super.key, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: p.card,
          border: Border.all(color: p.bd),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: warn ? p.warn : p.tx)),
        Text(label, style: TextStyle(fontSize: 13, color: p.mut)),
      ]),
    );
  }
}

/// Small rounded chip with a bold number (.chip in the demo).
class InfoChip extends StatelessWidget {
  final String label, value;
  final bool warn;
  const InfoChip(this.label, this.value, {super.key, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: warn ? p.warnbg : p.soft,
          borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(fontSize: 13, color: warn ? p.warn : p.tx)),
        const SizedBox(width: 6),
        Text(value,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: warn ? p.warn : p.tx)),
      ]),
    );
  }
}
