/*
 * $Id: mouse.d,v 1.1 2005/09/11 00:47:40 kenta Exp $
 *
 * Copyright 2005 Kenta Cho. Some rights reserved.
 */
module abagames.gr.mouse;

private import abagames.util.sdl.mouse;
private import abagames.util.sdl.screen;
private import abagames.gr.screen;

/**
 * Mouse input.
 */
public class RecordableMouse: abagames.util.sdl.mouse.RecordableMouse {
 private:
  SizableScreen screen;

  public this(SizableScreen screen) {
    super();
    this.screen = screen;
  }

  protected override void adjustPos(MouseState ms) {
    // Map the mouse position in the viewport to the visible world extent.
    alias GrScreen = abagames.gr.screen.Screen;
    ms.x =  (ms.x - (screen.screenStartX + screen.screenWidth  / 2)) * GrScreen.visibleWidth / screen.screenWidth;
    ms.y = -(ms.y - (screen.screenStartY + screen.screenHeight / 2)) * GrScreen.VISIBLE_HEIGHT / screen.screenHeight;
  }
}
