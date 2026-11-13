import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Console flow log. Prints one "[NAV hh:mm:ss.mmm] ..." line each time a page
/// or dialog is opened / closed, so together with the existing "[API] -> ..."
/// lines you can follow the whole flow of the app. Debug builds only.
///
/// Register once:  MaterialApp(navigatorObservers: [PageLogObserver()], ...)
/// Extra free-text lines (tabs, buttons):  navLog('tab -> ເອກະສານ');

String _now() {
  final t = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
}

void navLog(String msg) {
  if (kDebugMode) debugPrint('[NAV ${_now()}] $msg');
}

class PageLogObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];
  final Map<Route<dynamic>, String> _names = {};

  /// Page widget class (best effort), or the route type for dialogs / menus.
  String _nameOf(Route<dynamic> route) {
    final given = route.settings.name;
    if (given != null && given.isNotEmpty) return given;
    if (route is MaterialPageRoute) {
      try {
        final ctx = navigator?.context;
        if (ctx != null) return route.builder(ctx).runtimeType.toString();
      } catch (_) {}
    }
    final t = route.runtimeType.toString();
    return route is PageRoute ? t : 'popup:$t';
  }

  String _path() => _routes
      .whereType<PageRoute>()
      .map((r) => _names[r] ?? '?')
      .join(' > ');

  /// After the first frame: print the AppBar title, which tells apart pages that
  /// reuse the same class (for example the generic list / detail pages).
  void _title(Route<dynamic> route, String name) {
    if (route is! PageRoute) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final ctx = route.subtreeContext;
      if (ctx == null) return;
      Element? found;
      void visit(Element e) {
        if (found != null) return;
        if (e.widget is Scaffold) {
          found = e;
          return;
        }
        e.visitChildren(visit);
      }

      ctx.visitChildElements(visit);
      final sc = found?.widget;
      if (sc is Scaffold) {
        final ab = sc.appBar;
        if (ab is AppBar) {
          final t = ab.title;
          if (t is Text) {
            final s = t.data ?? t.textSpan?.toPlainText() ?? '';
            if (s.isNotEmpty) navLog('      title: $s   [$name]');
          }
        }
      }
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _nameOf(route);
    _names[route] = name;
    _routes.add(route);
    final from = previousRoute == null ? '' : (_names[previousRoute] ?? '');
    navLog('PUSH  $name${from.isEmpty ? '' : '   (from $from)'}');
    if (route is PageRoute) navLog('      path: ${_path()}');
    _title(route, name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _names.remove(route) ?? route.runtimeType.toString();
    _routes.remove(route);
    final back = previousRoute == null ? '' : (_names[previousRoute] ?? '');
    navLog('POP   $name${back.isEmpty ? '' : '   (back to $back)'}');
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _names.remove(route) ?? route.runtimeType.toString();
    _routes.remove(route);
    navLog('REMOVE $name');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    String oldName = '';
    if (oldRoute != null) {
      oldName = _names.remove(oldRoute) ?? oldRoute.runtimeType.toString();
      _routes.remove(oldRoute);
    }
    if (newRoute != null) {
      final name = _nameOf(newRoute);
      _names[newRoute] = name;
      _routes.add(newRoute);
      navLog('REPLACE $oldName -> $name');
      if (newRoute is PageRoute) navLog('      path: ${_path()}');
      _title(newRoute, name);
    }
  }
}
