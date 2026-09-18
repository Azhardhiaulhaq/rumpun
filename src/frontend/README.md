# Rumpun Flutter prototype

A phone-first Flutter prototype for the initial Rumpun flow:

- splash
- email login and password recovery feedback
- registration with email, Google, or Apple demo actions
- home with balance privacy control and transaction actions
- transaction review with editable confirmation and rejection
- explicit ready, loading, empty, and error states on data screens

All financial values, account names, and user initials are visibly marked or described as demo data. Authentication and persistence are local prototype behavior until the backend is connected.

## Run on a phone

1. Install Flutter and an Android SDK, accept the Android SDK licenses, and enable USB debugging on the phone.
2. Connect the phone and confirm that it appears under `flutter devices`.
3. Run with the local Android SDK and JDK 17:

```sh
cd src/frontend
ANDROID_HOME="$HOME/Android/Sdk" \
ANDROID_SDK_ROOT="$HOME/Android/Sdk" \
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
PATH="$HOME/Android/Sdk/platform-tools:/usr/lib/jvm/java-17-openjdk-amd64/bin:$PATH" \
flutter run
```

A ready-to-install debug APK is also available at `build/app/outputs/flutter-apk/app-debug.apk`.

## Prototype controls

On the home and review screens, the three-dot menu switches between data, loading, empty, and error states. This is only a review aid.

## Checks

```sh
cd src/frontend
flutter analyze
flutter test
```
