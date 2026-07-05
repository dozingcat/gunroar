/*
 * $Id: bullet.d,v 1.1.1.1 2005/06/18 00:46:00 kenta Exp $
 *
 * Copyright 2005 Kenta Cho. Some rights reserved.
 */
module abagames.gr.bullet;

private import std.math;
private import core.stdc.stdarg;
private import opengl;
private import abagames.util.actor;
private import abagames.util.vector;
private import abagames.util.math;
private import abagames.util.sdl.shape;
private import abagames.gr.gamemanager;
private import abagames.gr.field;
private import abagames.gr.ship;
private import abagames.gr.screen;
private import abagames.gr.enemy;
private import abagames.gr.shot;
private import abagames.gr.particle;
private import abagames.gr.crystal;
private import abagames.gr.shape;

/**
 * Enemy's bullets.
 */
public class Bullet: Actor {
 private:
  GameManager gameManager;
  Field field;
  Ship ship;
  SmokePool smokes;
  WakePool wakes;
  CrystalPool crystals;
  Vector _pos;
  Vector ppos;
  float _deg, _speed;
  float trgDeg, trgSpeed;
  float size;
  int cnt;
  float range;
  bool _destructive;
  BulletShape shape;
  int _enemyIdx;

  invariant() {
    assert(_pos.x < 15 && _pos.x > -15);
    assert(_pos.y < 40 && _pos.y > -20);
    assert(ppos.x < 15 && ppos.x > -15);
    assert(ppos.y < 40 && ppos.y > -20);
    assert(!std.math.isNaN(_deg));
    assert(!std.math.isNaN(trgDeg));
    assert(_speed > -5 && _speed < 10);
    assert(trgSpeed >= 0 && trgSpeed < 10);
    assert(size > 0 && size < 10);
    assert(range > -20);
  }

  public this() {
    _pos = new Vector;
    ppos = new Vector;
    shape = new BulletShape;
    _deg = trgDeg = 0;
    _speed = trgSpeed = 1;
    size = 1;
    range = 1;
  }

  public override void init(Object[] args) {
    gameManager = cast(GameManager) args[0];
    field = cast(Field) args[1];
    ship = cast(Ship) args[2];
    smokes = cast(SmokePool) args[3];
    wakes = cast(WakePool) args[4];
    crystals = cast(CrystalPool) args[5];
  }

  public void set(int enemyIdx,
                  Vector p, float d,
                  float sp, float size, int shapeType, float range,
                  float startSpeed = 0, float startDeg = -99999,
                  bool destructive = false) {
    if (!field.checkInOuterFieldExceptTop(p))
      return;
    _enemyIdx = enemyIdx;
    ppos.x = _pos.x = p.x;
    ppos.y = _pos.y = p.y;
    _speed = startSpeed;
    if (startDeg == -99999)
      _deg = d;
    else
      _deg = startDeg;
    trgDeg = d;
    trgSpeed = sp;
    this.size = size;
    this.range = range;
    _destructive = destructive;
    shape.set(shapeType);
    shape.size = size;
    cnt = 0;
    exists = true;
  }

  public override void move() {
    ppos.x = _pos.x;
    ppos.y = _pos.y;
    if (cnt < 30) {
      _speed += (trgSpeed - _speed) * 0.066f;
      float md = trgDeg - _deg;
      Math.normalizeDeg(md);
      _deg += md * 0.066f;
      if (cnt == 29) {
        _speed = trgSpeed;
        _deg = trgDeg;
      }
    }
    if (field.checkInOuterField(_pos))
      gameManager.addSlowdownRatio(_speed * 0.24f);
    const float degSin = sin(_deg);
    const float degCos = cos(_deg);
    float mx = degSin * _speed;
    float my = degCos * _speed;
    _pos.x += mx;
    _pos.y += my;
    _pos.y -= field.lastScrollY;
    if (ship.checkBulletHit(_pos, ppos) || !field.checkInOuterFieldExceptTop(_pos)) {
      remove();
      return;
    }
    cnt++;
    range -= _speed;
    if (range <= 0)
      startDisappear();
    if (field.getBlock(_pos) >= Field.ON_BLOCK_THRESHOLD)
      startDisappear();
  }

  public void startDisappear() {
    if (field.getBlock(_pos) >= 0) {
      Smoke s = smokes.getInstanceForced();
      const float degSin = sin(_deg);
      const float degCos = cos(_deg);
      s.set(_pos, degSin * _speed * 0.2f, degCos * _speed * 0.2f, 0,
            Smoke.SmokeType.SAND, 30, size * 0.5f);
    } else {
      Wake w = wakes.getInstanceForced();
      w.set(_pos, _deg, _speed, 60, size * 3, true);
    }
    remove();
  }

  public void changeToCrystal() {
    Crystal c = crystals.getInstance();
    if (c)
      c.set(_pos);
    remove();
  }

  public void remove() {
    exists = false;
  }

  public override void draw() {
    if (!field.checkInOuterField(_pos))
      return;
    glPushMatrix();
    Screen.glTranslate(_pos);
    if (_destructive) {
      glRotatef(cnt * 13, 0, 0, 1);
    } else {
      glRotatef(-_deg * 180 / PI, 0, 0, 1);
      glRotatef(cnt * 13, 0, 1, 0);
    }
    shape.draw();
    glPopMatrix();
  }

  public void checkShotHit(Vector p, Collidable s, Shot shot) {
    float ox = fabs(_pos.x - p.x), oy = fabs(_pos.y - p.y);
    if (ox + oy < 0.5f) {
    //if (shape.checkCollision(ox, oy, s)) {
      shot.removeHitToBullet();
      Smoke s1 = smokes.getInstance();
      if (s1) {
        const float degSin = sin(_deg);
        const float degCos = cos(_deg);
        s1.set(_pos, degSin * _speed, degCos * _speed, 0,
               Smoke.SmokeType.SPARK, 30, size * 0.5f);
      }
      remove();
    }
  }

  public bool destructive() {
    return _destructive;
  }

  public int enemyIdx() {
    return _enemyIdx;
  }

  public Vector pos() {
    return _pos;
  }

  public float deg() {
    return _deg;
  }

  public float speed() {
    return _speed;
  }
}

public class BulletPool: ActorPool!(Bullet) {
  public this(int n, Object[] args) {
    super(n, args);
  }

  public int removeIndexedBullets(int idx) {
    int n = 0;
    foreach (Bullet b; actor) {
      if (b.exists && b.enemyIdx == idx) {
        b.changeToCrystal();
        n++;
      }
    }
    return n;
  }

  public void checkShotHit(Vector pos, Collidable shape, Shot shot) {
    foreach (Bullet b; actor)
      if (b.exists && b.destructive)
        b.checkShotHit(pos, shape, shot);
  }
}
