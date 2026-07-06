/*
 * $Id: boot.d,v 1.6 2006/03/18 02:42:09 kenta Exp $
 *
 * Copyright 2005 Kenta Cho. Some rights reserved.
 */
module abagames.gr.boot;

private import std.string;
//private import std.stream;
private import std.conv;
private import std.math;
private import core.stdc.stdlib;
private import abagames.util.logger;
private import abagames.util.tokenizer;
private import abagames.util.sdl.mainloop;
private import abagames.util.sdl.input;
private import abagames.util.sdl.pad;
private import abagames.util.sdl.twinstick;
private import abagames.util.sdl.recordableinput;
private import abagames.util.sdl.sound;
private import abagames.gr.screen;
private import abagames.gr.field;
private import abagames.gr.gamemanager;
private import abagames.gr.prefmanager;
private import abagames.gr.ship;
private import abagames.gr.mouse;

/**
 * Boot the game.
 */
private:
Screen screen;
MultipleInputDevice input;
RecordablePad pad;
RecordableTwinStick twinStick;
RecordableMouse mouse;
GameManager gameManager;
PrefManager prefManager;
MainLoop mainLoop;

version (Android) {
  // Boot as an Android SDL application: SDLActivity loads libmain.so and
  // calls SDL_main with the arguments from GunroarActivity.getArguments().
  private import core.runtime;
  private import std.file;
  private import bindbc.sdl;
  private import abagames.gr.replay;

  private extern (C) void initialize_gl4es();

  extern (C) int SDL_main(int argc, char** argv) {
    // gl4es is built with NO_INIT_CONSTRUCTOR: running its initialization
    // inside dlopen (during Activity.onCreate) can hang the process, so it
    // is deferred to here — still before any EGL context exists, which is
    // what its hardware probing expects.
    initialize_gl4es();
    // We handle touch input directly; stop SDL from also synthesizing mouse
    // events from touches (and vice versa), which double-fires menu actions.
    SDL_SetHint("SDL_TOUCH_MOUSE_EVENTS", "0");
    SDL_SetHint("SDL_MOUSE_TOUCH_EVENTS", "0");
    int result = EXIT_FAILURE;
    Runtime.initialize();
    try {
      setupAndroidPaths();
      string[] args = ["gunroar"];
      for (int i = 1; i < argc; i++)
        args ~= to!string(argv[i]);
      result = boot(args);
    } catch (Throwable o) {
      Logger.error("Exception: " ~ o.toString());
    }
    Runtime.terminate();
    return result;
  }

  // Writable files (prefs, replays, options.ini) live in the app's pref
  // directory; read-only assets (images, sounds) load from the APK through
  // SDL_RWFromFile with their usual relative paths.
  private void setupAndroidPaths() {
    char* pp = SDL_GetPrefPath("abagames", "gunroar");
    if (pp == null)
      return;
    string prefDir = to!string(pp);
    PrefManager.PREF_FILE = prefDir ~ "gr.prf";
    ReplayData.dir = prefDir ~ "replay";
    try {
      mkdirRecurse(ReplayData.dir);
    } catch (Exception e) {}
    OPTIONS_INI_FILE = prefDir ~ "options.ini";
  }
} else version (Win32_release) {
  // Boot as the Windows executable.
  private import std.c.windows.windows;
  private import std.string;

  extern (C) void gc_init();
  extern (C) void gc_term();
  extern (C) void _minit();
  extern (C) void _moduleCtor();

  extern (Windows)
  public int WinMain(HINSTANCE hInstance,
		     HINSTANCE hPrevInstance,
		     LPSTR lpCmdLine,
		     int nCmdShow) {
    int result;
    gc_init();
    _minit();
    try {
      _moduleCtor();
      char[4096] exe;
      GetModuleFileNameA(null, exe, 4096);
      string[1] prog;
      prog[0] = to!string(exe);
      result = boot(prog ~ std.string.split(to!string(lpCmdLine)));
    } catch (Exception o) {
      Logger.error("Exception: " ~ o.toString());
      result = EXIT_FAILURE;
    }
    gc_term();
    return result;
  }
} else {
  // Boot as the general executable.
  public int main(string[] args) {
    return boot(args);
  }
}

public int boot(string[] args) {
  screen = new Screen;
  input = new MultipleInputDevice;
  pad = new RecordablePad;
  twinStick = new RecordableTwinStick;
  mouse = new RecordableMouse(screen);
  input.inputs ~= pad;
  input.inputs ~= twinStick;
  input.inputs ~= mouse;
  gameManager = new GameManager;
  prefManager = new PrefManager;
  mainLoop = new MainLoop(screen, input, gameManager, prefManager);
  try {
    parseArgs(args);
  } catch (Exception e) {
    return EXIT_FAILURE;
  }
  try {
    mainLoop.loop();
  } catch (Exception o) {
    Logger.info(o.toString());
    try {
      gameManager.saveErrorReplay();
    } catch (Exception o1) {}
    throw o;
  }
  return EXIT_SUCCESS;
}

// Parse an integer option value; non-numeric input prints the usage.
private int parseIntArg(string progName, string arg) {
  try {
    return to!int(arg);
  } catch (ConvException e) {
    usage(progName);
    throw new Exception("Invalid options");
  }
}

private void parseArgs(string[] commandArgs) {
  string[] args = readOptionsIniFile();
  for (int i = 1; i < commandArgs.length; i++)
    args ~= commandArgs[i];
  string progName = commandArgs[0];
  bool widescreen = false;
  bool resSpecified = false;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
    case "-brightness":
      if (i >= args.length - 1) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      i++;
      float b = cast(float) parseIntArg(progName, args[i]) / 100;
      if (b < 0 || b > 1) {
        usage(args[0]);
        throw new Exception("Invalid options");
      }
      Screen.brightness = b;
      break;
    case "-luminosity":
    case "-luminous":
      if (i >= args.length - 1) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      i++;
      float l = cast(float) parseIntArg(progName, args[i]) / 100;
      if (l < 0 || l > 1) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      screen.luminosity = l;
      break;
    case "-window":
      screen.windowMode = true;
      break;
    case "-fullscreen":
      screen.windowMode = false;
      break;
    case "-widescreen":
      widescreen = true;
      break;
    case "-retina":
      screen.highDpi = true;
      break;
    case "-noretina":
      screen.highDpi = false;
      break;
    case "-bot":
      GameManager.autoStartMode = InGameState.GameMode.BOT;
      break;
    case "-touchonly":
      InGameState.touchOnlyModes = true;
      break;
    case "-res":
      if (i >= args.length - 2) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      i++;
      int w = parseIntArg(progName, args[i]);
      i++;
      int h = parseIntArg(progName, args[i]);
      screen.screenWidth = w;
      screen.screenHeight = h;
      resSpecified = true;
      break;
    case "-nosound":
      SoundManager.noSound = true;
      break;
    case "-slowdown":
      // Intensity of the intentional slowdown under heavy fire:
      // 100 = original behavior, 0 = always run at full speed.
      if (i >= args.length - 1) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      i++;
      int sd = parseIntArg(progName, args[i]);
      if (sd < 0 || sd > 100) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      mainLoop.slowdownMaxRatio(1 + 0.75f * sd / 100);
      break;
    case "-exchange":
      pad.buttonReversed = true;
      break;
    case "-nowait":
      mainLoop.nowait = true;
      break;
    case "-accframe":
      mainLoop.accframe = 1;
      break;
    case "-turnspeed":
      if (i >= args.length - 1) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      i++;
      float s = cast(float) parseIntArg(progName, args[i]) / 100;
      if (s < 0 || s > 5) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      GameManager.shipTurnSpeed = s;
      break;
    case "-firerear":
      GameManager.shipReverseFire = true;
      break;
    case "-rotatestick2":
    case "-rotaterightstick":
      if (i >= args.length - 1) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      i++;
      twinStick.rotate = cast(float) parseIntArg(progName, args[i]) * PI / 180.0f;
      break;
    case "-reversestick2":
    case "-reverserightstick":
      twinStick.reverse = -1;
      break;
    case "-enableaxis5":
      twinStick.enableAxis5 = true;
      break;
    /*case "-mouseaccel":
      if (i >= args.length - 1) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      i++;
      float s = cast(float) parseIntArg(progName, args[i]) / 100;
      if (s < 0 || s > 5) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      mouse.accel = s;
      break;*/
    default:
      usage(progName);
      throw new Exception("Invalid options");
    }
  }
  if (widescreen) {
    screen.setWidescreen();
    Field.BLOCK_SIZE_X = 26;
    if (!resSpecified) {
      screen.screenWidth = 1280;
      screen.screenHeight = 720;
    }
  }
}

private string OPTIONS_INI_FILE = "options.ini";

private string[] readOptionsIniFile() {
  try {
    return Tokenizer.readFile(OPTIONS_INI_FILE, " ");
  } catch (Exception e) {
    return null;
  }
}

private void usage(string progName) {
  Logger.error
    ("Usage: " ~ progName ~ " [-window] [-fullscreen] [-widescreen] [-retina|-noretina] [-bot] [-touchonly] [-res x y] [-slowdown [0-100]] [-brightness [0-100]] [-luminosity [0-100]] [-nosound] [-exchange] [-turnspeed [0-500]] [-firerear] [-rotatestick2 deg] [-reversestick2] [-enableaxis5] [-nowait]");
}
