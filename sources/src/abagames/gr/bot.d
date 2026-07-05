/*
 * Autonomous player for the BOT game mode.
 */
module abagames.gr.bot;

private import std.math;
version (BOTDEBUG) {
  private import std.stdio;
}
private import abagames.util.vector;
private import abagames.util.sdl.twinstick;
private import abagames.gr.field;
private import abagames.gr.ship;
private import abagames.gr.bullet;
private import abagames.gr.enemy;

/**
 * Bot player: reads the visible game state each frame and produces a
 * twin-stick input state. It only uses information a human player can see
 * (positions and per-frame movement of bullets and enemies);
 * it does not inspect the RNG or simulate the game's future.
 */
public class Bot {
 private:
  static const int CANDIDATE_NUM = 16;
  static const int LOOKAHEAD_FRAMES = 40;
  static const float SHIP_SPEED = 0.15f;  // Boat.SPEED_BASE
  static const float SHOT_SPEED = 0.6f;   // Shot.SPEED
  static const int THREAT_MAX = 512;
  // Distance within which a target counts as engaged; beyond it the bot
  // gets bored and closes in.
  static const float ENGAGE_DIST = 10;
  Field field;
  Ship ship;
  BulletPool bullets;
  EnemyPool enemies;
  TwinStickState state;
  // Threats gathered per frame: position, per-frame velocity, danger radius.
  float[THREAT_MAX] thrX, thrY, thrVx, thrVy, thrR;
  int threatNum;
  // Rises while no target is within engagement range; drives aggression.
  int boredom;
  // Grid for the terrain path search (1-unit cells over the playfield).
  static const int GRID_SIZE_X = 32;
  static const int GRID_SIZE_Y = 24;
  int[GRID_SIZE_X * GRID_SIZE_Y] bfsDist;
  int[GRID_SIZE_X * GRID_SIZE_Y] bfsPrev;
  int[GRID_SIZE_X * GRID_SIZE_Y] bfsQueue;

  public this(Field field, Ship ship, BulletPool bullets, EnemyPool enemies) {
    this.field = field;
    this.ship = ship;
    this.bullets = bullets;
    this.enemies = enemies;
    state = new TwinStickState;
  }

  public TwinStickState getState() {
    state.clear();
    Vector sp = ship.midstPos;
    float sx = sp.x, sy = sp.y;
    gatherThreats(sx, sy);
    Enemy target = selectTarget(sx, sy);
    if (target is null ||
        target.pos.dist(sx, sy) - target.size * 0.5f > ENGAGE_DIST) {
      boredom++;
      if (boredom > 600)
        boredom = 600;
    } else {
      boredom -= 4;
      if (boredom < 0)
        boredom = 0;
    }
    selectMove(sx, sy, target);
    selectFire(sx, sy, target);
version (BOTDEBUG) {
    debugCnt++;
    if (debugCnt % 300 == 0) {
      writefln("bot: pos=(%.1f,%.1f) danger=%.2f threats=%d boredom=%d move=(%.1f,%.1f)",
               sx, sy, dangerLevel(sx, sy), threatNum, boredom, state.left.x, state.left.y);
      stdout.flush();
    }
}
    return state;
  }

version (BOTDEBUG) {
  int debugCnt;
}

  private void addThreat(float x, float y, float vx, float vy, float r) {
    if (threatNum >= THREAT_MAX)
      return;
    thrX[threatNum] = x;
    thrY[threatNum] = y;
    thrVx[threatNum] = vx;
    thrVy[threatNum] = vy;
    thrR[threatNum] = r;
    threatNum++;
  }

  private void gatherThreats(float sx, float sy) {
    threatNum = 0;
    // Bullets additionally drift down with the field scroll each frame.
    float scroll = field.lastScrollY;
    foreach (Bullet b; bullets.actor) {
      if (!b.exists)
        continue;
      Vector bp = b.pos;
      if (fabs(bp.x - sx) + fabs(bp.y - sy) > 20)
        continue;
      const float bDegSin = sin(b.deg);
      const float bDegCos = cos(b.deg);
      addThreat(bp.x, bp.y, bDegSin * b.speed, bDegCos * b.speed - scroll, 0.55f);
    }
    foreach (Enemy e; enemies.actor) {
      if (!e.exists || e.state.destroyedCnt >= 0)
        continue;
      Vector ep = e.state.pos;
      if (fabs(ep.x - sx) + fabs(ep.y - sy) > 20)
        continue;
      // Per-frame velocity from the visible movement since the last frame.
      float evx = ep.x - e.state.ppos.x;
      float evy = ep.y - e.state.ppos.y;
      addThreat(ep.x, ep.y, evx, evy, e.size * 0.7f + 0.4f);
    }
  }

  // How threatened the ship is right now (0 = safe, 1 = incoming fire),
  // from the closest approach of each threat over the lookahead window.
  private float dangerLevel(float sx, float sy) {
    float danger = 0;
    for (int t = 0; t < threatNum; t++) {
      float rx = thrX[t] - sx, ry = thrY[t] - sy;
      float vx = thrVx[t], vy = thrVy[t];
      float v2 = vx * vx + vy * vy;
      float tc = 0;
      if (v2 > 0.0001f)
        tc = -(rx * vx + ry * vy) / v2;
      if (tc < 0)
        tc = 0;
      else if (tc > LOOKAHEAD_FRAMES)
        tc = LOOKAHEAD_FRAMES;
      float cx = rx + vx * tc, cy = ry + vy * tc;
      float cd = sqrt(cx * cx + cy * cy);
      float rr = thrR[t] + 1.5f;
      if (cd < rr)
        danger += (1 - cd / rr) * (1 - tc / (LOOKAHEAD_FRAMES * 1.5f));
    }
    if (danger > 1)
      danger = 1;
    return danger;
  }

  // Breadth-first search over 1-unit water cells for a route toward the
  // top of the field. Returns false if the ship's cell has no open route
  // anywhere. The waypoint is a point a few steps along the route, so an
  // escape from a terrain pocket that first requires backtracking (away
  // from the scroll direction) is found naturally.
  private bool findAdvanceWaypoint(float sx, float sy, ref float wx, ref float wy) {
    int hw = cast(int) field.size.x;
    int hh = cast(int) field.size.y;
    int gw = hw * 2 + 1;
    int gh = hh * 2 + 1;
    if (gw > GRID_SIZE_X)
      gw = GRID_SIZE_X;
    if (gh > GRID_SIZE_Y)
      gh = GRID_SIZE_Y;
    int sgx = cast(int) floor(sx + 0.5f) + hw;
    int sgy = cast(int) floor(sy + 0.5f) + hh;
    if (sgx < 0)
      sgx = 0;
    else if (sgx >= gw)
      sgx = gw - 1;
    if (sgy < 0)
      sgy = 0;
    else if (sgy >= gh)
      sgy = gh - 1;
    bfsDist[0 .. gw * gh] = -1;
    int qh = 0, qt = 0;
    // Start from the ship's cell, or an open neighbor if it overlaps land.
    for (int oy = 0; oy <= 2 && qt == 0; oy++) {
      for (int ox = -1; ox <= 1 && qt == 0; ox++) {
        int gx = sgx + ox, gy = sgy + (oy == 2 ? -1 : oy);
        if (gx < 0 || gx >= gw || gy < 0 || gy >= gh)
          continue;
        if (field.getBlock(gx - hw, gy - hh) >= 0)
          continue;
        int ci = gx + gy * gw;
        bfsDist[ci] = 0;
        bfsPrev[ci] = -1;
        bfsQueue[qt++] = ci;
      }
    }
    if (qt == 0)
      return false;
    static const int[4] NBX = [0, 1, 0, -1];
    static const int[4] NBY = [1, 0, -1, 0];  // prefer upward expansion
    int goal = -1;
    int highest = bfsQueue[0];
    while (qh < qt) {
      int ci = bfsQueue[qh++];
      int cx = ci % gw, cy = ci / gw;
      if (cy > highest / gw)
        highest = ci;
      if (cy == gh - 1) {
        goal = ci;
        break;
      }
      for (int n = 0; n < 4; n++) {
        int nx = cx + NBX[n], ny = cy + NBY[n];
        if (nx < 0 || nx >= gw || ny < 0 || ny >= gh)
          continue;
        int ni = nx + ny * gw;
        if (bfsDist[ni] >= 0)
          continue;
        if (field.getBlock(nx - hw, ny - hh) >= 0)
          continue;
        bfsDist[ni] = bfsDist[ci] + 1;
        bfsPrev[ni] = ci;
        bfsQueue[qt++] = ni;
      }
    }
    // If the top is unreachable, head for the highest reachable water.
    if (goal < 0)
      goal = highest;
    // Walk back so the waypoint is at most a few steps from the ship.
    static const int WAYPOINT_STEPS = 5;
    int wi = goal;
    while (bfsDist[wi] > WAYPOINT_STEPS)
      wi = bfsPrev[wi];
    wx = wi % gw - hw;
    wy = wi / gw - hh;
    return true;
  }

  private void selectMove(float sx, float sy, Enemy target) {
    // Boredom ramps up after ~2s without an engaged target, maxing at ~6s.
    float bore = (boredom - 120) / 240.0f;
    if (bore < 0)
      bore = 0;
    else if (bore > 1)
      bore = 1;
    float danger = dangerLevel(sx, sy) * (1 - 0.5f * bore);
    // Cruise target: follow the terrain route toward the top of the field
    // to raise the scroll speed and the rank multiplier.
    float tgtX = 0, tgtY = field.size.y * 0.9f;
    bool escaping = false;
    float wpX, wpY;
    if (findAdvanceWaypoint(sx, sy, wpX, wpY)) {
      tgtX = wpX;
      tgtY = wpY;
      // A route that starts by backing up means the ship is in a closing
      // terrain pocket; get out immediately, before the scroll shuts it.
      if (wpY < sy - 0.5f)
        escaping = true;
    }
    // When bored, close on the target to a standoff distance instead.
    if (!escaping && bore > 0 && target !is null) {
      float ex = target.pos.x, ey = target.pos.y;
      float dx = ex - sx, dy = ey - sy;
      float d = sqrt(dx * dx + dy * dy);
      float standoff = target.size * 0.5f + ENGAGE_DIST * 0.85f;
      if (d > standoff) {
        float apX = ex - dx / d * standoff;
        float apY = ey - dy / d * standoff;
        tgtX += (apX - tgtX) * bore;
        tgtY += (apY - tgtY) * bore;
      }
    }
    // Advance hard when safe; when under fire the threat terms dominate.
    // Boredom adds its own pull so long standoffs cannot last forever.
    float attract = 0.25f + (1 - danger) * 1.25f + bore;
    if (escaping)
      attract += 1.5f;
    // A bored bot accepts less personal space around threats (the hard
    // collision penalty below is unaffected) and commits on a shorter
    // lookahead, so dense fire ahead does not read as an absolute wall.
    float softPenalty = 10 * (1 - 0.7f * bore);
    int lookahead = LOOKAHEAD_FRAMES - cast(int) (bore * 16);
    float scroll = field.lastScrollY;
    float bottomY = -field.size.y * 0.96f;
    float bestScore = -1e30f;
    int bestDir = -1;
    for (int i = -1; i < CANDIDATE_NUM; i++) {
      float mvx = 0, mvy = 0;
      if (i >= 0) {
        float a = i * PI * 2 / CANDIDATE_NUM;
        mvx = sin(a) * SHIP_SPEED;
        mvy = cos(a) * SHIP_SPEED;
      }
      float score = 0;
      // Slight bias for holding position to avoid dithering.
      if (i == -1)
        score += 0.1f;
      float px = sx, py = sy;
      for (int k = 1; k <= lookahead; k++) {
        // The ship passively drifts down with the water it sits on.
        px += mvx;
        py += mvy - scroll;
        bool atBottom = false;
        if (px < -field.size.x) {
          px = -field.size.x;
          score -= 2.0f / k;
        } else if (px > field.size.x) {
          px = field.size.x;
          score -= 2.0f / k;
        }
        if (py < bottomY) {
          py = bottomY;
          atBottom = true;
        } else if (py > field.size.y * 0.96f) {
          py = field.size.y * 0.96f;
          score -= 2.0f / k;
        }
        // The ground will have scrolled down k frames by then; sample it
        // at the correspondingly higher current position.
        if (field.getBlock(px, py + scroll * k) >= 0) {
          if (atBottom) {
            // Squeezed between the ground and the bottom of the screen:
            // that is certain death, avoid it at all costs.
            score -= 400.0f / k;
          } else {
            score -= 12.0f / k;
            px -= mvx;
            py -= mvy;
          }
        }
        // Earlier collisions weigh more.
        float w = cast(float) (lookahead - k + 8) / lookahead;
        for (int t = 0; t < threatNum; t++) {
          float ox = thrX[t] + thrVx[t] * k - px;
          float oy = thrY[t] + thrVy[t] * k - py;
          float r = thrR[t];
          float d2 = ox * ox + oy * oy;
          if (d2 < r * r)
            score -= 100 * w;
          else if (d2 < (r + 0.7f) * (r + 0.7f))
            score -= softPenalty * w;
        }
      }
      float tox = tgtX - px, toy = tgtY - py;
      score -= sqrt(tox * tox + toy * toy) * attract;
      if (score > bestScore) {
        bestScore = score;
        bestDir = i;
      }
    }
    if (bestDir >= 0) {
      float a = bestDir * PI * 2 / CANDIDATE_NUM;
      state.left.x = sin(a);
      state.left.y = cos(a);
    }
  }

  private Enemy selectTarget(float sx, float sy) {
    Enemy target = null;
    float minDist = 1e30f;
    foreach (Enemy e; enemies.actor) {
      if (!e.exists || e.state.destroyedCnt >= 0)
        continue;
      Vector ep = e.state.pos;
      if (fabs(ep.x) > field.outerSize.x || fabs(ep.y) > field.outerSize.y + 3)
        continue;
      float d = (ep.x - sx) * (ep.x - sx) + (ep.y - sy) * (ep.y - sy);
      // Prefer clearing the path ahead over chasing enemies behind.
      if (ep.y < sy)
        d += 64;
      if (d < minDist) {
        minDist = d;
        target = e;
      }
    }
    return target;
  }

  private void selectFire(float sx, float sy, Enemy target) {
    // Aim at the target with simple leading.
    if (!target)
      return;
    float ex = target.state.pos.x, ey = target.state.pos.y;
    float evx = ex - target.state.ppos.x;
    float evy = ey - target.state.ppos.y;
    float t = 0;
    for (int i = 0; i < 2; i++) {
      float ox = ex + evx * t - sx;
      float oy = ey + evy * t - sy;
      t = sqrt(ox * ox + oy * oy) / SHOT_SPEED;
    }
    float aimX = ex + evx * t - sx;
    float aimY = ey + evy * t - sy;
    float al = sqrt(aimX * aimX + aimY * aimY);
    if (al < 0.01f)
      return;
    state.right.x = aimX / al;
    state.right.y = aimY / al;
  }
}
