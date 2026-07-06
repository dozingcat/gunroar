#!/bin/sh
# Build the Android APK.
#
# Prerequisites (see android/README.md):
#   - LDC (brew install ldc) plus the matching ldc2-<ver>-android-aarch64
#     runtime package
#   - Android SDK with NDK, and Android-built SDL2 / SDL2_mixer / gl4es
#   - Paths below can be overridden via environment variables.

set -e
cd "$(dirname "$0")"

DEPS="${GUNROAR_ANDROID_DEPS:-$(pwd)/../android-deps}"
SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
NDK_VER="${GUNROAR_NDK_VERSION:-29.0.13599879}"
LDC_ANDROID_LIBS="$DEPS/ldc2-1.42.0-android-aarch64/lib"
PREFIX="$DEPS/android-prefix"
NDK_BIN="$SDK/ndk/$NDK_VER/toolchains/llvm/prebuilt/darwin-x86_64/bin"
# Use Android Studio's bundled JDK regardless of the shell's JAVA_HOME.
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export JAVA_HOME

TRIPLE=aarch64--linux-android30
JNILIBS=../android/app/src/main/jniLibs/arm64-v8a
ASSETS=../android/app/src/main/assets

SOURCES="import/*.d import/sdl/*.d import/bindbc/sdl/*.d \
src/abagames/util/*.d src/abagames/util/sdl/*.d src/abagames/gr/*.d"

echo "== Generating Android ldc2 config =="
LDC_INCLUDE="$(dirname "$(dirname "$(command -v ldc2)")")/include/dlang/ldc"
cat > "$DEPS/ldc2-android.conf" <<EOF
"default":
{
    switches = [
        "-defaultlib=phobos2-ldc,druntime-ldc",
        "-link-defaultlib-shared=false",
    ];
    post-switches = [
        "-I$LDC_INCLUDE",
    ];
    lib-dirs = [
        "$LDC_ANDROID_LIBS",
    ];
    rpath = "";
};
EOF

echo "== Compiling D game to libmain.so =="
ldc2 -conf="$DEPS/ldc2-android.conf" \
  -of=libmain.so -O -release -shared -relocation-model=pic \
  -mtriple=$TRIPLE \
  -d-version=BindSDL_Static -d-version=SDL_201 -d-version=SDL_Mixer_202 \
  -I=import -I=src \
  $SOURCES \
  -gcc="$NDK_BIN/aarch64-linux-android30-clang" \
  -L-L"$PREFIX/lib" -L-lSDL2 -L-lSDL2_mixer -L-lGL \
  -L-lm -L-llog \
  -L-Wl,-soname,libmain.so

echo "== Assembling jniLibs and assets =="
mkdir -p $JNILIBS $ASSETS
cp libmain.so $JNILIBS/
cp "$PREFIX/lib/libSDL2.so" "$PREFIX/lib/libSDL2_mixer.so" "$PREFIX/lib/libGL.so" $JNILIBS/
rm -rf $ASSETS/images $ASSETS/sounds
cp -R ../images ../sounds $ASSETS/

echo "== Building APK =="
cd ../android
./gradlew --console=plain -q assembleDebug
echo "APK: android/app/build/outputs/apk/debug/app-debug.apk"
