#!/bin/sh
# Build for macOS using LDC (brew install ldc sdl2 sdl2_mixer).
# GLU is provided by the system OpenGL framework.

cd "$(dirname "$0")" || exit 1

BREW_PREFIX=$(brew --prefix)

SOURCES="import/*.d import/sdl/*.d import/bindbc/sdl/*.d \
src/abagames/util/*.d src/abagames/util/sdl/*.d src/abagames/gr/*.d"

ldc2 -of=Gunroar -O -release \
  -d-version=BindSDL_Static -d-version=SDL_201 -d-version=SDL_Mixer_202 \
  -I=import -I=src \
  $SOURCES \
  -L-L"$BREW_PREFIX/lib" -L-lSDL2 -L-lSDL2_mixer \
  -L-framework -LOpenGL
