/*
 * $Id: pad.d,v 1.2 2005/07/03 07:05:23 kenta Exp $
 *
 * Copyright 2004 Kenta Cho. Some rights reserved.
 */
module abagames.util.sdl.pad;

version(PANDORA) version = PANDORA_OR_PYRA;
version(PYRA) version = PANDORA_OR_PYRA;

version (PANDORA) {
  private import std.conv;
}
private import std.string;
private import std.stdio;
private import bindbc.sdl;
version (Android) {
  private import sdl.log;
}
private import abagames.util.sdl.input;
private import abagames.util.sdl.recordableinput;

/**
 * Joystick and keyboard input.
 */
public class Pad: Input {
 public:
  ubyte *keys;
  bool buttonReversed = false;
 private:
  SDL_Joystick *stick = null;
  const int JOYSTICK_AXIS = 16384;
  PadState state;
version (Android) {
 public:
  // Taps act as pad input for the menus: a tap on the game-mode text
  // (bottom left) cycles the mode, a tap anywhere else is button A. The
  // top-right corner is a pause/end-game zone (see InGameState.move).
  static const int TOUCH_ZONE_NONE = 0;
  static const int TOUCH_ZONE_A = 1;
  static const int TOUCH_ZONE_MODE = 2;
  static const int TOUCH_ZONE_PAUSE = 3;
  static const float PAUSE_ZONE_X = 0.90f;
  static const float PAUSE_ZONE_Y = 0.15f;
 private:
  static const int TOUCH_MAX = 10;
  static const int TOUCH_ZONE_NUM = 4;
  long[TOUCH_MAX] touchId;
  int[TOUCH_MAX] touchZone;
  // A tap can begin and end inside one frame's event batch; latch each
  // zone's finger-down for one full frame so game logic never misses it.
  bool[TOUCH_ZONE_NUM] zonePending;
  bool[TOUCH_ZONE_NUM] zoneLatched;
  SDL_TouchID touchDev = 0;
}

  public this() {
    state = new PadState;
  }

  public SDL_Joystick* openJoystick(SDL_Joystick *st = null) {
    if (st == null) {
      if (SDL_InitSubSystem(SDL_INIT_JOYSTICK) < 0)
        return null;
      version (PANDORA) {
        foreach (i; 0..SDL_NumJoysticks()) {
          if (to!string(SDL_JoystickNameForIndex(i)) == "nub0") {
            stick = SDL_JoystickOpen(i);
          }
        }
      } else {
        stick = SDL_JoystickOpen(0);
      }
    } else {
      stick = st;
    }
    return stick;
  }

  public void handleEvent(SDL_Event *event) {
version (Android) {
    switch (event.type) {
    case SDL_FINGERDOWN:
      touchDev = event.tfinger.touchId;
      foreach (i; 0 .. TOUCH_MAX) {
        if (touchZone[i] == TOUCH_ZONE_NONE) {
          touchId[i] = event.tfinger.fingerId;
          if (event.tfinger.x > PAUSE_ZONE_X && event.tfinger.y < PAUSE_ZONE_Y)
            touchZone[i] = TOUCH_ZONE_PAUSE;
          else if (event.tfinger.x < 0.30f && event.tfinger.y > 0.75f)
            touchZone[i] = TOUCH_ZONE_MODE;
          else
            touchZone[i] = TOUCH_ZONE_A;
          zonePending[touchZone[i]] = true;
          break;
        }
      }
      break;
    case SDL_FINGERUP:
      foreach (i; 0 .. TOUCH_MAX) {
        if (touchZone[i] != TOUCH_ZONE_NONE && touchId[i] == event.tfinger.fingerId)
          touchZone[i] = TOUCH_ZONE_NONE;
      }
      break;
    default:
      break;
    }
}
  }

  public void handleEvents() {
    keys = SDL_GetKeyboardState(null);
version (Android) {
    zoneLatched[] = zonePending[];
    zonePending[] = false;
    // A finger release can be lost (e.g. the system gesture navigation
    // steals the touch); when no fingers remain on the screen, sweep any
    // leaked slots so a phantom press cannot pin the input forever.
    if (touchDev != 0 && SDL_GetNumTouchFingers(touchDev) == 0) {
      foreach (i; 0 .. TOUCH_MAX) {
        if (touchZone[i] != TOUCH_ZONE_NONE) {
          SDL_Log("touch slot %d leaked (zone=%d); cleared", cast(int) i, touchZone[i]);
          touchZone[i] = TOUCH_ZONE_NONE;
        }
      }
    }
}
  }

  public PadState getState() {
    int x = 0, y = 0;
    state.dir = 0;
    if (stick) {
      x = SDL_JoystickGetAxis(stick, 0);
      y = SDL_JoystickGetAxis(stick, 1);
    }
    if (keys[SDL_SCANCODE_RIGHT] == SDL_PRESSED || keys[SDL_SCANCODE_KP_6] == SDL_PRESSED ||
        keys[SDL_SCANCODE_D] == SDL_PRESSED || keys[SDL_SCANCODE_L] == SDL_PRESSED ||
        x > JOYSTICK_AXIS)
      state.dir |= PadState.Dir.RIGHT;
    if (keys[SDL_SCANCODE_LEFT] == SDL_PRESSED || keys[SDL_SCANCODE_KP_4] == SDL_PRESSED ||
        keys[SDL_SCANCODE_A] == SDL_PRESSED || keys[SDL_SCANCODE_J] == SDL_PRESSED ||
        x < -JOYSTICK_AXIS)
      state.dir |= PadState.Dir.LEFT;
    if (keys[SDL_SCANCODE_DOWN] == SDL_PRESSED || keys[SDL_SCANCODE_KP_2] == SDL_PRESSED ||
        keys[SDL_SCANCODE_S] == SDL_PRESSED || keys[SDL_SCANCODE_K] == SDL_PRESSED ||
        y > JOYSTICK_AXIS)
      state.dir |= PadState.Dir.DOWN;
    if (keys[SDL_SCANCODE_UP] == SDL_PRESSED ||  keys[SDL_SCANCODE_KP_8] == SDL_PRESSED ||
        keys[SDL_SCANCODE_W] == SDL_PRESSED || keys[SDL_SCANCODE_I] == SDL_PRESSED ||
        y < -JOYSTICK_AXIS)
      state.dir |= PadState.Dir.UP;
    state.button = 0;
    bool btnx = false, btnz = false;
    int btn1 = 0, btn2 = 0;
    float leftTrigger = 0, rightTrigger = 0;
    version(PYRA) {
    } else {
      if (stick) {
        btn1 = SDL_JoystickGetButton(stick, 0) + SDL_JoystickGetButton(stick, 3) +
               SDL_JoystickGetButton(stick, 4) + SDL_JoystickGetButton(stick, 7) +
               SDL_JoystickGetButton(stick, 8) + SDL_JoystickGetButton(stick, 11);
        btn2 = SDL_JoystickGetButton(stick, 1) + SDL_JoystickGetButton(stick, 2) +
               SDL_JoystickGetButton(stick, 5) + SDL_JoystickGetButton(stick, 6) +
               SDL_JoystickGetButton(stick, 9) + SDL_JoystickGetButton(stick, 10);
      }
    }
    version (PANDORA_OR_PYRA) {
      if (keys[SDL_SCANCODE_HOME] == SDL_PRESSED || keys[SDL_SCANCODE_PAGEUP] == SDL_PRESSED) btnz = true;
      if (keys[SDL_SCANCODE_PAGEDOWN] == SDL_PRESSED || keys[SDL_SCANCODE_END] == SDL_PRESSED) btnx = true;
    } else {
      if (keys[SDL_SCANCODE_Z] == SDL_PRESSED || keys[SDL_SCANCODE_PERIOD] == SDL_PRESSED ||
          keys[SDL_SCANCODE_LCTRL] == SDL_PRESSED || keys[SDL_SCANCODE_RCTRL] == SDL_PRESSED ||
          btn1) btnz = true;
      if (keys[SDL_SCANCODE_X] == SDL_PRESSED || keys[SDL_SCANCODE_SLASH] == SDL_PRESSED ||
          keys[SDL_SCANCODE_LALT] == SDL_PRESSED || keys[SDL_SCANCODE_RALT] == SDL_PRESSED ||
          keys[SDL_SCANCODE_LSHIFT] == SDL_PRESSED || keys[SDL_SCANCODE_RSHIFT] == SDL_PRESSED ||
          keys[SDL_SCANCODE_RETURN] == SDL_PRESSED ||
          btn2) btnx = true;
    }
    if (btnz) {
      if (!buttonReversed)
        state.button |= PadState.Button.A;
      else
        state.button |= PadState.Button.B;
    }
    if (btnx) {
      if (!buttonReversed)
        state.button |= PadState.Button.B;
      else
        state.button |= PadState.Button.A;
    }
version (Android) {
    foreach (i; 0 .. TOUCH_MAX) {
      if (touchZone[i] == TOUCH_ZONE_A)
        state.button |= PadState.Button.A;
      else if (touchZone[i] == TOUCH_ZONE_MODE)
        state.dir |= PadState.Dir.DOWN;
      // TOUCH_ZONE_PAUSE feeds no pad state; see touchInZone.
    }
    if (zoneLatched[TOUCH_ZONE_A])
      state.button |= PadState.Button.A;
    if (zoneLatched[TOUCH_ZONE_MODE])
      state.dir |= PadState.Dir.DOWN;
}
    return state;
  }

version (Android) {
  public bool touchInZone(int zone) {
    if (zoneLatched[zone])
      return true;
    foreach (i; 0 .. TOUCH_MAX) {
      if (touchZone[i] == zone)
        return true;
    }
    return false;
  }
}

  public PadState getNullState() {
    state.clear();
    return state;
  }

}

public class PadState {
 public:
  static enum Dir {
    UP = 1, DOWN = 2, LEFT = 4, RIGHT = 8,
  };
  static enum Button {
    A = 16, B = 32, ANY = 48,
  };
  int dir, button;
 private:

  public static PadState newInstance() {
    return new PadState;
  }

  public static PadState newInstance(PadState s) {
    return new PadState(s);
  }

  public this() {
  }

  public this(PadState s) {
    this();
    set(s);
  }

  public void set(PadState s) {
    dir = s.dir;
    button = s.button;
  }

  public void clear() {
    dir = button = 0;
  }

  public void read(File fd) {
    int[1] read_data;
    fd.rawRead(read_data);
    dir = read_data[0] & (Dir.UP | Dir.DOWN | Dir.LEFT | Dir.RIGHT);
    button = read_data[0] & Button.ANY;
  }

  public void write(File fd) {
    int[1] write_data = [dir | button];
    fd.rawWrite(write_data);
  }

  public bool equals(PadState s) {
    if (dir == s.dir && button == s.button)
      return true;
    else
      return false;
  }
}

public class RecordablePad: Pad {
  mixin RecordableInput!(PadState);
 private:

  public override PadState getState() {
    return getState(true);
  }

  public PadState getState(bool doRecord) {
    PadState s = super.getState();
    if (doRecord)
      record(s);
    return s;
  }
}
