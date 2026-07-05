# Gunroar

Guns, Guns, Guns!

360-degree gunboat shooter, 'Gunroar'.

## How to play

Steer a boat and sink enemy fleet.

Rank multiplier (displayed in the upper right) is a bonus multiplier that increases with a difficulty of a game. You can increase a rank multiplier faster by going forward faster.

Boss appearance timer (displayed in the upper left) is a remaining time before a boss ship appears.

## Building on macOS

Install the dependencies with [Homebrew](https://brew.sh):

```sh
brew install ldc sdl2 sdl2_mixer
```

Then build and run from the repository root:

```sh
sources/buildMacOS.sh
./sources/Gunroar
```

The game must be launched from the repository root so it can find the `images/` and `sounds/` directories.

Useful command line options:

- `-fullscreen` — run fullscreen at the desktop resolution (default is a resizable window)
- `-widescreen` — 16:9 mode with a wider playfield (default is the original 4:3 game)
- `-noretina` — render at non-Retina resolution (Retina rendering is on by default)
- `-bot` — start directly in BOT mode, where an autonomous player steers and fires (also selectable as a game mode on the title screen)

Options can also be placed in an `options.ini` file in the working directory (space-separated) to apply them on every launch.
<hr/>

The game was created by [Kenta Cho](https://www.asahi-net.or.jp/~cs8k-cyu/windows/gr_e.html "Kenta Cho - Gunroar") and released with BSD 2-Clause License. (See readme.txt/readme_e.txt)

This is a fork of https://github.com/M-HT/gunroar, and adds a macOS build and widescreen and high-DPI support.

It uses [BindBC-SDL](https://github.com/BindBC/bindbc-sdl "BindBC-SDL") (D bindings to SDL), which is under [Boost Software License](https://www.boost.org/LICENSE_1_0.txt "Boost Software License").
