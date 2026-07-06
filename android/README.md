# Gunroar for Android

An Android port of Gunroar (arm64-v8a, min API 30), using SDL2 and
[gl4es](https://github.com/ptitSeb/gl4es) to translate the game's OpenGL 1.x
rendering to OpenGL ES — the same approach as the Pandora/Pyra ports.

## Prerequisites

- LDC (`brew install ldc`) plus the matching `ldc2-<version>-android-aarch64`
  runtime package from the [LDC releases](https://github.com/ldc-developers/ldc/releases).
- Android SDK with an NDK and CMake (installed via Android Studio).
- Android-built shared libraries for **SDL2**, **SDL2_mixer**, and **gl4es**.

The Android runtime libs and native dependencies are **not** checked in. By
default the build script expects them under `android-deps/` at the repository
root (gitignored):

```
android-deps/
  ldc2-1.42.0-android-aarch64/lib/    # LDC Android runtime (matches brew LDC)
  android-prefix/lib/                 # libSDL2.so, libSDL2_mixer.so, libGL.so
```

Build the native deps with the NDK CMake toolchain (`-DANDROID_ABI=arm64-v8a
-DANDROID_PLATFORM=android-30`). For gl4es, configure with `-DANDROID=ON
-DNOX11=ON`; edit `src/CMakeLists.txt` so the `.so.1` suffix line is gated
`AND NOT ANDROID`, so the produced library's soname is plain `libGL.so`.

Override locations with `GUNROAR_ANDROID_DEPS`, `ANDROID_SDK_ROOT`, and
`GUNROAR_NDK_VERSION` if your layout differs.

## Building

```sh
sources/buildAndroid.sh
```

This cross-compiles the game to `libmain.so`, stages it and the native libs
into `android/app/src/main/jniLibs/arm64-v8a/`, copies `images/` and `sounds/`
into the APK assets, and runs `gradlew assembleDebug`. The APK lands at
`android/app/build/outputs/apk/debug/app-debug.apk`.

## Notes

- API level 30+ is required: earlier bionic lacks symbols the D runtime needs.
- Log output (from the game's `Logger`) goes to logcat under the tag `SDL/APP`.
- Prefs and replays are written to the app's private storage
  (`SDL_GetPrefPath`); read-only assets load from the APK by relative path.
- The Java sources in `app/src/main/java/org/libsdl/app/` are copied
  unmodified from the SDL2 source release (`android-project/` template).
  SDL2 has no official Maven/registry artifact, and these classes declare
  the JNI bridge into `libSDL2.so`, so they must stay in lockstep with the
  SDL version the native library is built from. When upgrading SDL: rebuild
  `libSDL2.so` and re-copy `org/libsdl/app/` from the same tarball. All of
  our customization lives in the `GunroarActivity` subclass. (SDL3 ships an
  official `.aar` that would replace these files if the port ever migrates.)
