import 'main_shell.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'screens.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TT Stock',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final w = mq.size.width > 1200 ? 1200.0 : mq.size.width;
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Center(
            child: SizedBox(
              width: w,
              child: MediaQuery(
                data: mq.copyWith(size: Size(w, mq.size.height)),
                child: child!,
              ),
            ),
          ),
        );
      },
      home: ValueListenableBuilder<bool>(
        valueListenable: loggedIn,
        builder: (_, ok, __) => ok ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }
}
