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
      home: ValueListenableBuilder<bool>(
        valueListenable: loggedIn,
        builder: (_, ok, __) => ok ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }
}
