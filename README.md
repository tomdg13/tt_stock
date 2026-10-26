# ATM Stock app (Flutter)

Android app for the ATM stock / terminal API (95 routes under `/api`).

## Build the APK (needs the Flutter SDK, 3.x)

In an empty folder run `flutter create --org la.ldb --project-name atm_stock_app .`,
then copy this project's `lib/` folder and `pubspec.yaml` over the generated ones.

Android needs the INTERNET permission. Add this line inside `<manifest>` in
`android/app/src/main/AndroidManifest.xml`, above `<application`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Then:

```bash
flutter pub get
flutter run                  # test on a device or emulator
flutter build apk --release  # output: build/app/outputs/flutter-apk/app-release.apk
```

## Server URL

Default (set in `lib/api.dart`):
`https://dehome.ldblao.la/atm-api/v1/endpointAtmstock/api`
It can also be changed in the app: gear icon on the login screen, or More > Settings.
