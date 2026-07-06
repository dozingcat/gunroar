package com.dozingcatsoftware.gunroar;

import android.content.res.Configuration;
import android.view.InputDevice;

import java.util.ArrayList;

import org.libsdl.app.SDLActivity;

public class GunroarActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        // Load order matters: gl4es (libGL) and SDL2_mixer before the game.
        return new String[] {
            "SDL2",
            "SDL2_mixer",
            "GL",
            "main"
        };
    }

    @Override
    protected String[] getArguments() {
        ArrayList<String> args = new ArrayList<String>();
        args.add("-fullscreen");
        args.add("-widescreen");
        if (!hasPhysicalKeyboardOrMouse()) {
            // Touchscreen only: limit the title menu to playable modes.
            args.add("-touchonly");
        }
        return args.toArray(new String[0]);
    }

    private boolean hasPhysicalKeyboardOrMouse() {
        if (getResources().getConfiguration().keyboard == Configuration.KEYBOARD_QWERTY) {
            return true;
        }
        for (int id : InputDevice.getDeviceIds()) {
            InputDevice dev = InputDevice.getDevice(id);
            if (dev == null || dev.isVirtual()) {
                continue;
            }
            int sources = dev.getSources();
            if ((sources & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE) {
                return true;
            }
            if (dev.getKeyboardType() == InputDevice.KEYBOARD_TYPE_ALPHABETIC) {
                return true;
            }
        }
        return false;
    }
}
