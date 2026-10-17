-- title:   Pip's Peak (lesson 17)
-- author:  TIC-80 Platformer Course
-- desc:    Power-ups
-- script:  lua

-- == Constants ==
local BTN_LEFT = 2
local BTN_RIGHT = 3
local BTN_A = 4   -- A is the Z key
local ANIM_IDLE = {256, 257}
local ANIM_RUN = {258, 259, 260, 261}
local SPR_JUMP = 262
local SPR_FALL = 263
local SPR_SQUASH = 265
local SPR_HURT = 264
local ANIM_COIN = {288, 289, 290, 291}
local SPR_GEM = 292
local SPR_HUD_COIN = 354
local SPR_HUD_GEM = 355
local SPR_HEART = 352
local SPR_HEART_EMPTY = 353
local SPR_HUD_PIP = 359
local SPR_CHECK_DOWN = 297
local SPR_CHECK_UP = 298
local ANIM_SLIME = {272, 273}
local SPR_SLIME_FLAT = 274
local ANIM_BAT = {275, 276}
local SPR_TURRET = 277
local SPR_BULLET = 278
local ANIM_SPIKY = {279, 280}
local SPR_HUD_FEATHER = 356
local SPR_HUD_BOOTS = 357
local SPR_HUD_STAR = 358

local F_SOLID = 0       -- sprite flag 0 marks tiles you can stand on
local F_HAZARD = 1      -- sprite flag 1 marks tiles that hurt (spikes)
local F_BONUS = 4       -- sprite flag 4 marks ?-blocks
local M_START = 50      -- marker tiles: where Pip starts the level,
local M_COIN, M_GEM = 48, 49   -- and where the coins and gems are
local M_CHECKPOINT = 51
local M_SLIME = 53
local M_BAT = 54
local M_TURRET = 55
local M_SPIKY = 56
local MAX_HP, START_LIVES = 3, 3
local COINS_PER_LIFE = 50

-- ?-blocks: the tile id says what is inside
local B_COIN = 16
local B_HEART = 17
local B_FEATHER = 18
local B_BOOTS = 19
local B_STAR = 20
local T_USED_BLOCK = 21
local ITEM_SPRITE = {
  [B_HEART] = 293, [B_FEATHER] = 294,
  [B_BOOTS] = 295, [B_STAR] = 296
}
local BOOTS_TIME, STAR_TIME = 600, 480   -- frames (10 s, 8 s)
local INVULNERABLE = 90  -- frames of safety after getting hurt

-- Each level is a rectangle of the map, in cells.
local LEVELS = {
  {
    name = "GREEN MEADOW", x = 0,
    y = 0, w = 120, h = 17, sky = 10,
    music = 1
  },
}

-- Sound effects: the numbers of the SFX made in the SFX editor
local SND = {
  JUMP = 0, COIN = 1, STOMP = 2,
  HURT = 3, POWER_UP = 4, BUMP = 5,
  SHOOT = 7, CHECKPOINT = 10,
  ONE_UP = 11, GEM = 12, MENU = 13,
  DIE = 14
}
local SFX_CHANNEL = 3   -- channels 0-2 play the music
-- Music: the track numbers from the music editor
local MUS = {
  TITLE = 0, OVERWORLD = 1,
  GAME_OVER = 5
}

-- Everything that decides how Pip feels, in one place to tune.
-- Speeds are pixels per frame; accelerations are pixels per frame per frame.
local P = {
  run_speed = 1.5,   -- top running speed
  accel = 0.25,      -- speeding up on the ground
  air_accel = 0.15,  -- steering in the air
  friction = 0.3,    -- slowing down when no direction is held
  gravity = 0.25,
  jump_speed = -4,
  jump_cut = -1.5,
  max_fall = 4,
  coyote = 6,        -- frames you can still jump after running off a ledge
  buffer = 6,        -- frames a jump press is remembered before landing
}

-- == State ==
-- x, y is the top-left corner of Pip's hitbox, a 6x8 box (the sprite is
-- drawn one pixel to the left so the box sits in the middle of it)
player = {
  x = 0, y = 0, w = 6, h = 8, vx = 0,
  vy = 0, flip = 0, moving = false,
  ground = false, jumping = false,
  coyote = 0, buffer = 0, squash = 0,
  hp = MAX_HP, invul = 0,
  feather = false, air_jump = false,
  boots = 0, star = 0
}
t = 0
cam = {x = 0, y = 0}   -- the top-left corner of the screen, in level pixels
state = "title"        -- "title", "play", "dead" or "gameover"
state_t = 0            -- frames since the state started
level = 1              -- which level we're on
lvl = LEVELS[1]        -- that level's table
start_x, start_y = 0, 0
level_t = 0            -- frames since the level started
score, coins, gems = 0, 0, 0
lives = START_LIVES
ents = {}    -- entities: everything in the level that moves or can be touched
parts = {}   -- particles: little dots that fly and fade

-- == Collision ==
-- Is the map tile at cell (tx, ty) solid? The level's left and right
-- edges count as walls, so Pip can't walk out of it.
function solid_at(tx, ty)
  if tx < lvl.x
      or tx >= lvl.x + lvl.w then
    return true
  end
  return fget(mget(tx, ty), F_SOLID)
end

-- Does a w x h box at pixel (x, y) overlap any solid tile?
function box_hits(x, y, w, h)
  for ty = y // 8, (y + h - 1) // 8 do
    for tx = x // 8,
        (x + w - 1) // 8 do
      if solid_at(tx, ty) then
        return true
      end
    end
  end
  return false
end

-- Does the box touch a tile with the given flag? (no level walls here)
function box_touches(x, y, w, h, flag)
  for ty = y // 8, (y + h - 1) // 8 do
    for tx = x // 8,
        (x + w - 1) // 8 do
      if fget(mget(tx, ty), flag) then
        return true
      end
    end
  end
  return false
end

-- Move e sideways by dx; if that runs into a wall, push it back out.
-- Returns true when it hit something.
function move_x(e, dx)
  e.x = e.x + dx
  if not box_hits(e.x, e.y, e.w, e.h)
  then
    return false
  end
  if dx > 0 then
    e.x =
      (e.x + e.w - 1) // 8 * 8 - e.w   -- just left of the wall
  else
    e.x = e.x // 8 * 8 + 8                  -- just right of the wall
  end
  return true
end

-- Move e up or down by dy, the same way.
function move_y(e, dy)
  e.y = e.y + dy
  if not box_hits(e.x, e.y, e.w, e.h)
  then
    return false
  end
  if dy > 0 then
    e.y =
      (e.y + e.h - 1) // 8 * 8 - e.h   -- standing on the tile
  else
    e.y = e.y // 8 * 8 + 8                  -- head against the ceiling
  end
  return true
end

-- == Sound ==
-- sfx(id, note, duration, channel): a nil note keeps the note the SFX was
-- made with (an explicit -1 would play the lowest note), and duration -1
-- lets it play out.
function play(id)
  sfx(id, nil, -1, SFX_CHANNEL)
end

-- == Entities ==
-- An entity is a table with a box (x, y, w, h) and two functions:
-- update(e) runs every frame, draw(e) draws it. Setting e.dead = true
-- removes it.
function add_ent(e)
  ents[#ents + 1] = e
  return e
end

-- Do two boxes overlap?
function overlaps(a, b)
  return a.x < b.x + b.w
    and b.x < a.x + a.w and a.y < b.y
    + b.h and b.y < a.y + a.h
end

function update_ents()
  -- walk the list backwards so removing an entry doesn't skip the next one
  for i = #ents, 1, -1 do
    local e = ents[i]
    e.update(e)
    if e.dead then
      table.remove(ents, i)
    end
  end
end

function draw_ents()
  for _, e in ipairs(ents) do
    e.draw(e)
  end
end

-- == Particles ==
function burst(x, y, n, color)
  for _ = 1, n do
    parts[#parts + 1] = {
      x = x, y = y,
      vx = math.random() * 2 - 1,
      vy = math.random() * -2,
      life = 20 + math.random(10),
      color = color
    }
  end
end

function update_parts()
  for i = #parts, 1, -1 do
    local d = parts[i]
    d.x, d.y, d.vy = d.x + d.vx,
      d.y + d.vy, d.vy + 0.1
    d.life = d.life - 1
    if d.life <= 0 then
      table.remove(parts, i)
    end
  end
end

function draw_parts()
  for _, d in ipairs(parts) do
    pix(d.x - cam.x, d.y - cam.y,
        d.color)
  end
end

-- == Pickups ==
function new_coin(x, y)
  add_ent({
    x = x + 1, y = y + 1, w = 6,
    h = 6, update = update_pickup,
    draw = draw_coin, kind = "coin"
  })
end

function new_gem(x, y)
  add_ent({
    x = x + 1, y = y + 1, w = 6,
    h = 6, update = update_pickup,
    draw = draw_gem, kind = "gem"
  })
end

-- Every COINS_PER_LIFE coins earn an extra life.
function add_coins(n)
  local before =
    coins // COINS_PER_LIFE
  coins = coins + n
  if coins // COINS_PER_LIFE
      > before then
    lives = lives + 1
    play(SND.ONE_UP)
  else
    play(SND.COIN)
  end
end

function update_pickup(e)
  if overlaps(player, e) then
    e.dead = true
    if e.kind == "coin" then
      add_coins(1)
      score = score + 10
      burst(e.x + 3, e.y + 3, 6, 4)
    else
      gems = gems + 1
      score = score + 500
      burst(e.x + 3, e.y + 3, 12, 11)
      play(SND.GEM)
    end
  end
end

function draw_coin(e)
  spr(anim_frame(ANIM_COIN, 8), e.x
      - 1 - cam.x, e.y - 1 - cam.y, 0)
end

function draw_gem(e)
  local bob =
    math.sin(t / 10) * 2 // 1   -- float up and down
  spr(SPR_GEM, e.x - 1 - cam.x,
      e.y - 1 - cam.y + bob, 0)
end

-- == Checkpoints ==
function new_checkpoint(x, y)
  add_ent({
    x = x, y = y, w = 8, h = 8,
    update = update_checkpoint,
    draw = draw_checkpoint, on = false
  })
end

function update_checkpoint(e)
  if not e.on
      and overlaps(player, e) then
    e.on = true
    start_x, start_y = e.x + 1, e.y   -- respawn here from now on
    burst(e.x + 3, e.y, 10, 5)
    play(SND.CHECKPOINT)
  end
end

function draw_checkpoint(e)
  spr(e.on and SPR_CHECK_UP
      or SPR_CHECK_DOWN, e.x - cam.x,
      e.y - cam.y, 0)
end

-- == Enemies ==
-- Every enemy has e.enemy = true. Touching one hurts Pip, unless Pip lands
-- on its head: that's a stomp.
function new_slime(x, y)
  add_ent({
    x = x + 1, y = y + 2, w = 6,
    h = 6, vx = -0.4, vy = 0,
    enemy = true,
    update = update_walker,
    draw = draw_slime, squashed = 0
  })
end

-- Is there floor just past the front edge of e? (so it can turn at ledges)
function floor_ahead(e)
  local fx =
    e.vx > 0 and e.x + e.w or e.x - 1
  return box_hits(fx, e.y + e.h, 1, 1)
end

function update_walker(e)
  if e.squashed > 0 then          -- flattened: wait a moment, then vanish
    e.squashed = e.squashed - 1
    if e.squashed == 0 then
      e.dead = true
    end
    return
  end
  e.vy = math.min(e.vy + P.gravity,
      P.max_fall)
  if move_y(e, e.vy) then e.vy = 0 end
  -- walk; turn around at walls, and at ledges when standing on something
  local on_ground =
    box_hits(e.x, e.y + 1, e.w, e.h)
  if move_x(e, e.vx) or (on_ground
        and not floor_ahead(e)) then
    e.vx = -e.vx
  end
  if e.y > (lvl.y + lvl.h) * 8 then
    e.dead = true
  end
  touch_enemy(e)
end

-- Pip touches an enemy: stomp it if Pip is falling onto its head.
function touch_enemy(e)
  local p = player
  if not overlaps(p, e) then
    return
  end
  if p.star > 0 then             -- star power: anything Pip touches is gone
    e.dead = true
    score = score + 100
    burst(e.x + 3, e.y + 3, 10, 4)
    play(SND.STOMP)
    return
  end
  local was_above =
    p.y + p.h - p.vy <= e.y + 2   -- feet were above its head last frame
  if p.vy > 0 and was_above then
    stomp(e)
  else
    hurt(e.x + e.w / 2)
  end
end

function stomp(e)
  if e.spiky then          -- never stomp on a spiky!
    hurt(e.x + e.w / 2)
    return
  end
  if e.squashed == nil then  -- enemies without a squashed sprite just pop
    e.dead = true
  else
    e.squashed = 20
  end
  e.vx = 0
  score = score + 100
  burst(e.x + 3, e.y + 3, 8, 6)
  play(SND.STOMP)
  -- bounce off its head; higher if the jump button is held
  player.vy = btn(BTN_A)
    and P.jump_speed or -2.5
  player.jumping = btn(BTN_A)    -- a high bounce can be cut short, like a jump
end

function draw_slime(e)
  local id =
    e.squashed > 0 and SPR_SLIME_FLAT
    or anim_frame(ANIM_SLIME, 12)
  spr(id, e.x - 1 - cam.x,
      e.y - 2 - cam.y, 0, 1,
      e.vx > 0 and 1 or 0)
end

-- A spiky walks like a slime, but its back is covered in spikes.
function new_spiky(x, y)
  add_ent({
    x = x + 1, y = y + 2, w = 6,
    h = 6, vx = -0.3, vy = 0,
    enemy = true, spiky = true,
    update = update_walker,
    draw = draw_spiky, squashed = 0
  })
end

function draw_spiky(e)
  spr(anim_frame(ANIM_SPIKY, 10), e.x
      - 1 - cam.x, e.y - 2 - cam.y, 0,
      1, e.vx > 0 and 1 or 0)
end

-- A bat swoops left and right around where it started, bobbing up and down.
function new_bat(x, y)
  add_ent({
    x = x + 1, y = y + 2, w = 6,
    h = 5, home_x = x, home_y = y,
    enemy = true, vx = 0, vy = 0,
    phase = (x // 8) % 7,
    update = update_bat,
    draw = draw_bat
  })
end

function update_bat(e)
  local a = (t + e.phase * 20) / 60
  local new_x =
    e.home_x + math.sin(a) * 32
  e.vx = new_x - e.x                -- remember the direction for drawing
  e.x = new_x
  e.y = e.home_y + math.sin(a * 3) * 6
  touch_enemy(e)
end

function draw_bat(e)
  spr(anim_frame(ANIM_BAT, 6), e.x - 1
      - cam.x, e.y - 2 - cam.y, 0, 1,
      e.vx > 0 and 1 or 0)
end

-- A turret sits still and fires at Pip when Pip is close.
function new_turret(x, y)
  add_ent({
    x = x, y = y, w = 8, h = 8,
    vy = 0, enemy = true, reload = 60,
    update = update_turret,
    draw = draw_turret
  })
end

function update_turret(e)
  e.reload = e.reload - 1
  local dx = player.x - e.x
  if e.reload <= 0 and math.abs(dx)
      < 120 and math.abs(player.y
        - e.y) < 48 then
    new_bullet(e.x + 2, e.y + 2,
        dx < 0 and -1.5 or 1.5)
    e.reload = 90
    play(SND.SHOOT)
  end
  touch_enemy(e)
end

function draw_turret(e)
  spr(SPR_TURRET, e.x - cam.x,
      e.y - cam.y, 0, 1,
      player.x > e.x and 1 or 0)
end

-- Bullets fly straight until they hit a wall, Pip, or time out.
function new_bullet(x, y, vx)
  add_ent({
    x = x, y = y, w = 4, h = 4,
    vx = vx, life = 180,
    update = update_bullet,
    draw = draw_bullet
  })
end

function update_bullet(e)
  e.x = e.x + e.vx
  e.life = e.life - 1
  if e.life <= 0 or box_hits(e.x, e.y,
        e.w, e.h) then
    e.dead = true
    burst(e.x + 2, e.y + 2, 4, 3)
  elseif overlaps(player, e) then
    e.dead = true
    hurt(e.x)
  end
end

function draw_bullet(e)
  spr(SPR_BULLET, e.x - 2 - cam.x,
      e.y - 2 - cam.y, 0)
end

-- == Power-ups ==
-- Pip's head hit something solid: open any ?-block above it.
function bump_head(p)
  local ty = (p.y - 1) // 8
  for tx = p.x // 8,
      (p.x + p.w - 1) // 8 do
    local tile = mget(tx, ty)
    if fget(tile, F_BONUS) then
      open_block(tx, ty, tile)
    end
  end
end

function open_block(tx, ty, tile)
  mset(tx, ty, T_USED_BLOCK)
  play(SND.BUMP)
  if tile == B_COIN then
    add_coins(1)
    score = score + 10
    burst(tx * 8 + 4,
        ty * 8 - 2, 8, 4)
  else
    new_item(tx * 8, ty * 8, tile)
  end
end

-- An item slides up out of its block, then waits to be picked up.
function new_item(x, y, kind)
  add_ent({
    x = x + 1, y = y, w = 6, h = 6,
    top = y - 7, kind = kind, vx = 0,
    vy = 0, rising = true,
    landed = false,
    update = update_item,
    draw = draw_item
  })
end

function update_item(e)
  if e.rising then
    e.y = e.y - 0.5
    if e.y <= e.top then          -- out of the block: slide away from Pip
      e.rising = false
      e.vx = player.x < e.x and 0.75
        or -0.75
    end
  elseif not e.landed then
    -- slide off the block and drop to the ground, like a walker
    if move_x(e, e.vx) then
      e.vx = -e.vx
    end
    e.vy = math.min(e.vy + P.gravity,
        P.max_fall)
    if move_y(e, e.vy) then
      -- down off the blocks and onto something: stay there
      if e.y > e.top + 4 then
        e.landed = true
      end
      e.vy = 0
    end
  end
  if not e.rising
      and overlaps(player, e) then
    e.dead = true
    power_up(e.kind)
  end
end

function draw_item(e)
  local bob = e.landed and (
      math.sin(t / 8) // 1 - 1) or 0   -- never below the ground
  spr(ITEM_SPRITE[e.kind],
      e.x - 1 - cam.x,
      e.y - 1 - cam.y + bob, 0)
end

function power_up(kind)
  local p = player
  if kind == B_HEART then
    p.hp = math.min(p.hp + 1, MAX_HP)
  elseif kind == B_FEATHER then
    p.feather = true                 -- a second jump in the air, until hurt
  elseif kind == B_BOOTS then
    p.boots = BOOTS_TIME             -- run faster for a while
  elseif kind == B_STAR then
    p.star = STAR_TIME               -- nothing can hurt Pip for a while
  end
  score = score + 1000
  burst(p.x + 3, p.y + 4, 16, 4)
  play(SND.POWER_UP)
end

-- == Health ==
-- Lose a heart, unless Pip is still blinking from the last hit.
-- from_x says where the hit came from, to knock Pip away from it.
function hurt(from_x)
  local p = player
  if p.invul > 0 or p.star > 0
      or state ~= "play" then
    return
  end
  p.hp = p.hp - 1
  p.feather = false
  if p.hp <= 0 then
    lose_life()
    return
  end
  p.invul = INVULNERABLE
  p.vx = p.x < from_x and -2 or 2
  p.vy = -2.5
  p.jumping = false
  play(SND.HURT)
end

function lose_life()
  lives = lives - 1
  set_state("dead")
  play(SND.DIE)
  player.vy = -4        -- a little hop, then fall off the screen
end

-- == HUD ==
function draw_hud()
  rect(0, 0, 240, 9, 0)
  print(string.format("%06d", score),
      4, 2, 12, true)
  for i = 1, MAX_HP do
    spr(i <= player.hp and SPR_HEART
        or SPR_HEART_EMPTY,
        160 + (i - 1) * 8, 0, 0)
  end
  spr(SPR_HUD_PIP, 204, 1, 0)
  print("x" .. lives, 213, 2,
      12, true)
  -- power-ups, with seconds left
  local x = 112
  if player.feather then
    spr(SPR_HUD_FEATHER, x, 0, 0); x =
      x + 10
  end
  if player.boots > 0 then
    spr(SPR_HUD_BOOTS, x, 0, 0)
    print(player.boots // 60 + 1, x
        + 9, 2, 12, true); x = x + 16
  end
  if player.star > 0 then
    spr(SPR_HUD_STAR, x, 0, 0)
    print(player.star // 60 + 1,
        x + 9, 2, 12, true)
  end
  spr(SPR_HUD_COIN, 46, 0, 0)
  print("x" .. coins, 55, 2, 12, true)
  spr(SPR_HUD_GEM, 80, 0, 0)
  print(gems .. "/3", 89, 2, 12, true)
end

-- == Helpers ==
-- Move v toward target by at most step.
function approach(v, target, step)
  if v < target then
    return math.min(v + step, target)
  end
  return math.max(v - step, target)
end

-- == Animation ==
function anim_frame(frames, speed)
  return
    frames[(t // speed) % #frames + 1]
end

-- == Player ==
function update_player(p)
  -- run: accelerate toward the top speed, or slide to a stop
  local dir = 0
  if btn(BTN_LEFT) then
    dir = dir - 1
  end
  if btn(BTN_RIGHT) then
    dir = dir + 1
  end
  if dir ~= 0 then
    p.flip = dir < 0 and 1 or 0
    local speed =
      p.boots > 0 and P.run_speed
      * 1.5 or P.run_speed
    p.vx = approach(p.vx, dir * speed,
        p.ground and P.accel
        or P.air_accel)
  else
    p.vx = approach(p.vx, 0, p.ground
        and P.friction or P.air_accel)
  end
  p.moving = p.vx ~= 0
  if move_x(p, p.vx) then p.vx = 0 end

  -- coyote time: count down from the moment Pip leaves the ground
  if p.ground then
    p.coyote = P.coyote
  else
    p.coyote =
      math.max(0, p.coyote - 1)
  end
  -- jump buffer: remember a press for a few frames
  if btnp(BTN_A) then
    p.buffer = P.buffer
  else
    p.buffer =
      math.max(0, p.buffer - 1)
  end
  if p.ground then   -- landing gives the feather's jump back
    p.air_jump = p.feather
  end
  if p.buffer > 0 and (p.coyote > 0
        or p.air_jump) then
    if p.coyote == 0 then   -- that was the jump in the air
      p.air_jump = false
    end
    p.vy = P.jump_speed
    p.jumping = true
    p.buffer, p.coyote = 0, 0
    play(SND.JUMP)
  end
  -- let go early for a short hop (only a jump Pip started can be cut short)
  if p.jumping and not btn(BTN_A)
      and p.vy < P.jump_cut then
    p.vy = P.jump_cut
  end
  if p.vy >= 0 then
    p.jumping = false
  end

  p.vy = math.min(p.vy + P.gravity,
      P.max_fall)
  local fall_speed = p.vy
  if move_y(p, p.vy) then
    if p.vy < 0 then bump_head(p) end
    p.vy = 0
  end
  local was_on_ground = p.ground
  p.ground =
    box_hits(p.x, p.y + 1, p.w, p.h)
  if p.ground and p.vy >= 0 then
    if not was_on_ground   -- a hard landing squashes Pip
        and fall_speed > 2 then
      p.squash = 6
    end
    p.vy = 0
    p.y = p.y // 1
  end
  p.squash = math.max(0, p.squash - 1)

  p.invul = math.max(0, p.invul - 1)
  p.boots = math.max(0, p.boots - 1)
  p.star = math.max(0, p.star - 1)
  -- spikes: test a slightly smaller box, so only a real touch hurts
  if box_touches(p.x + 1, p.y + 2, p.w
        - 2, p.h - 2, F_HAZARD) then
    hurt(p.x
        + (p.flip == 0 and 8 or -8))
  end
  -- fell below the level
  if p.y > (lvl.y + lvl.h) * 8 then
    lose_life()
  end
end

function draw_player(p)
  -- blink while invulnerable: skip drawing every other 4 frames
  if p.invul > 0
      and p.invul // 4 % 2 == 1 then
    return
  end
  local id
  if state == "dead" or p.invul
      > INVULNERABLE - 20 then
    id = SPR_HURT
  elseif p.squash > 0 then
    id = SPR_SQUASH
  elseif not p.ground then
    if p.vy < 0 then
      id = SPR_JUMP
    else
      id = SPR_FALL
    end
  elseif p.moving then
    id = anim_frame(ANIM_RUN, 6)
  else
    id = anim_frame(ANIM_IDLE, 30)
  end
  if p.star > 0 then
    -- the palette map (0x3FF0) swaps colors while drawing: poke4 writes
    -- one 4-bit entry, so entry 6 (Pip's green) becomes a cycling color
    poke4(0x3FF0 * 2 + 6,
        2 + t // 4 % 4)
  end
  -- everything in the level is drawn relative to the camera
  spr(id, p.x - 1 - cam.x,
      p.y - cam.y, 0, 1, p.flip)
  poke4(0x3FF0 * 2 + 6, 6)                 -- put green back
end

-- == Camera ==
function clamp(v, lo, hi)
  return math.max(lo, math.min(v, hi))
end

-- Keep Pip in the middle of the screen, but never show outside the level.
function update_camera()
  local left, top =
    lvl.x * 8, lvl.y * 8
  local right, bottom = left + lvl.w
    * 8 - 240, top + lvl.h * 8 - 136
  cam.x = clamp(player.x + player.w
      // 2 - 120, left, right) // 1
  cam.y = clamp(player.y + player.h
      // 2 - 68, top, bottom) // 1
end

-- Far-away hills scroll slower than the level: that's parallax.
function draw_background()
  cls(lvl.sky)
  clip(0, 0, 240, 112)          -- hills only above the ground line: pits show sky
  local far = cam.x * 0.25 // 1
  for i = 0, 3 do
    local hx = i * 96 - far % 96
    circ(hx, 140, 56, 13)        -- pale far hills
  end
  local near = cam.x * 0.5 // 1
  for i = 0, 4 do
    local hx = i * 64 - near % 64
    circ(hx + 32, 134, 30, 7)    -- darker, closer hills
  end
  clip()
end

-- == Levels ==
-- Marker tiles in the map say where things go. The loader replaces each
-- marker with an empty cell and calls its spawn function with the
-- marker's pixel position.
SPAWN = {
  [M_START] = function(x, y) start_x,
  start_y = x + 1, y end,
  [M_COIN] = new_coin,
  [M_GEM] = new_gem,
  [M_CHECKPOINT] = new_checkpoint,
  [M_SLIME] = new_slime,
  [M_BAT] = new_bat,
  [M_TURRET] = new_turret,
  [M_SPIKY] = new_spiky,
}

function reset_player()
  local p = player
  p.x, p.y, p.vx, p.vy =
    start_x, start_y, 0, 0
  p.flip, p.squash, p.coyote,
    p.buffer = 0, 0, 0, 0
  p.hp, p.invul = MAX_HP, 0
  p.feather, p.air_jump, p.boots,
    p.star = false, false, 0, 0
end

-- Start level n from the beginning (a new level, or a new game).
function load_level(n)
  level, lvl = n, LEVELS[n]
  ents, parts = {}, {}
  gems = 0            -- each level has its own three gems
  sync(4, 0, false)   -- copy the map from the cart back into RAM (4 = map), undoing old mset()s
  for ty = lvl.y, lvl.y + lvl.h - 1 do
    for tx = lvl.x,
        lvl.x + lvl.w - 1 do
      local spawn =
        SPAWN[mget(tx, ty)]
      if spawn then
        mset(tx, ty, 0)
        spawn(tx * 8, ty * 8)
      end
    end
  end
  reset_player()
  update_camera()
  level_t = 0
end

-- == States ==
function set_state(s)
  local before = state
  state, state_t = s, 0
  -- each state has its own music; music() with no track stops it
  if s == "title" then
    music(MUS.TITLE)
  elseif s == "play"
      and before ~= "play" then
    music(lvl.music)
  elseif s == "dead" then
    music()
  elseif s == "gameover" then
    music(MUS.GAME_OVER, -1,
        -1, false)   -- frame, row, loop: play once
  end
end

function update_title()
  if btnp(BTN_A) then
    play(SND.MENU)
    score, coins, gems, lives =
      0, 0, 0, START_LIVES
    load_level(1)
    set_state("play")
  end
end

-- Print text centered across the screen. print() returns the width of what
-- it drew, so measure the text off-screen first.
function print_centered(text, y,
      color, scale)
  scale = scale or 1
  local w = print(text, 0, -100,
      color, false, scale)
  print(text, (240 - w) // 2, y,
      color, false, scale)
end

function draw_title()
  cls(8)
  print("PIP'S PEAK", 41, 30, 0,
      false, 3)   -- shadow
  print("PIP'S PEAK", 39, 28, 4,
      false, 3)
  spr(anim_frame(ANIM_RUN, 6), 116,
      64, 0, 1, 0)
  if t // 30 % 2 == 0 then
    print_centered("PRESS Z TO START",
        96, 12)
  end
end

-- The level's name, for the first two seconds.
function draw_banner()
  if level_t > 120 then return end
  local w = print(lvl.name, 0, -16, 0,
      false, 2)   -- print returns the text width
  print(lvl.name, (240 - w) // 2 + 1,
      41, 0, false, 2)
  print(lvl.name, (240 - w) // 2, 40,
      12, false, 2)
end

function update_play()
  level_t = level_t + 1
  update_player(player)
  update_ents()
  update_parts()
  update_camera()
end

-- Pip hops and falls off the screen; then respawn at the last checkpoint.
function update_dead()
  player.vy = player.vy + P.gravity
  player.y = player.y + player.vy
  update_parts()
  if state_t > 90 then
    if lives > 0 then
      reset_player()   -- the level stays as it is: coins you took stay taken
      set_state("play")
    else
      set_state("gameover")
    end
  end
end

function update_gameover()
  if state_t > 60 and btnp(BTN_A) then
    set_state("title")
  end
end

function draw_gameover()
  cls(0)
  print_centered("GAME OVER",
      50, 2, 2)
  print_centered("SCORE " .. score,
      74, 12)
  if state_t > 60 then
    print_centered("PRESS Z", 96, 13)
  end
end

function draw_play()
  draw_background()
  -- draw the 31x18 cells under the screen, shifted by what's left of the
  -- camera position after whole cells (so the map scrolls pixel by pixel)
  map(cam.x // 8, cam.y // 8, 31, 18,
      -(cam.x % 8), -(cam.y % 8), 0)
  draw_ents()
  draw_player(player)
  draw_parts()
  draw_hud()
  draw_banner()
end

-- == Game loop ==
function BOOT()
  music(MUS.TITLE)
end

function TIC()
  t = t + 1
  state_t = state_t + 1
  if state == "title" then
    update_title()
    draw_title()
  elseif state == "play" then
    update_play()
    draw_play()
  elseif state == "dead" then
    update_dead()
    draw_play()
  elseif state == "gameover" then
    update_gameover()
    draw_gameover()
  end
end

-- <TILES>
-- 001:0555555655656565566666666266662611222222122321221122223212212222
-- 002:5565556556565656666666662666266622222222222321221222223222212222
-- 003:6555555056565655666666656266662622222211222321211222223122212221
-- 004:1222222212232122122222321221222212222322132222121222222211221222
-- 005:2222222222232122122222322221222222222322232222122222222222122212
-- 006:2222222122232121122222312221222122222321232222112222222122122111
-- 013:00000000000000000c000c000cf00cf0cdf0cdf0cdf0cdf0cdffcdffffffffff
-- 016:3333333334444443343cc44334444c433444c443344444433444c44333333333
-- 017:3333333334444443343cc44334444c433444c443344444433444c44333333333
-- 018:3333333334444443343cc44334444c433444c443344444433444c44333333333
-- 019:3333333334444443343cc44334444c433444c443344444433444c44333333333
-- 020:3333333334444443343cc44334444c433444c443344444433444c44333333333
-- 021:fffffffffeeeeeeffedeedeffeeeeeeffeeeeeeffedeedeffeeeeeefffffffff
-- 024:0000000000000000000000000066660006655660665666566566656666666666
-- 025:0000000000020000002420000002000000060000060600000066060000066600
-- 026:0000000000000000000000006000006060600650560606060565660600605605
-- 028:0000000000000000030003003433343303000300343334330300030003000300
-- 029:00000000000000000000cccc00cccccc0cccccccccccccccdddddddd00000000
-- 030:00cccc000cccccc0ccccccccccccccccccccccccccccccccdddddddd00000000
-- 031:0000000000000000cccc0000cccccc00ccccccc0ccccccccdddddddd00000000
-- 034:000000000333330003cc443003444c4303cc4430033333000003000000030000
-- 048:00444400044444404443c4444434c4444434c4444443c4440444444000444400
-- 049:0000000000bbbb000bcbbab0bccbbaab0bbbaab000baab00000ab00000000000
-- 050:0050000005500000666666006c4c460064444600066660000600600066006600
-- 051:0d0000000d2200000d2220000d2200000d0000000d0000000d000000eeee0000
-- 053:000000000000000000066000006556000656c660066c66606666666606666660
-- 054:0000000010000001110110111111c111011c1110001111000001100000000000
-- 055:0000000000ffff000feeeef0ffe22eefffeeeeef0feeeef0ffffffffeeeeeeee
-- 056:000000000c0c0c00c2c2c2c02222222c22c2c222222222200300030033003300
-- </TILES>

-- <SPRITES>
-- 000:00050000005500000666666066644f4666644446066666600660066003300330
-- 001:0000000000050000005560000666666066644f46666444460666666003300330
-- 002:00050000005500000666666066644f4666644446066666606600060030000330
-- 003:0000000000050000005560000666666066644f46666444460666666000336300
-- 004:00050000005500000666666066644f4666644446066666600060006603300003
-- 005:0000000000050000005560000666666066644f46666444460666666000363300
-- 006:00050000005500000666666066644f4666644446066666606600006630000003
-- 007:00500500000550000666666066644f4666644446066666600660066003000030
-- 008:002002000002200006666660666c4c4666644c46066666606600006630000003
-- 009:0000000000000000000500000055000066666666666644f66666666633000033
-- 016:00000000000000000006600000655600065c6c60066f6f606666666606666660
-- 017:00000000000000000000000000666600065c6c60656f6f66666c666666666666
-- 018:00000000000000000000000000000000000000000066660006c66c6066666666
-- 019:0000000020000002220110222211c112021c1120002112000001100000000000
-- 020:0000000000000000000110000221c2202211c112202112020001100000000000
-- 021:0000000000eeee000edddde0eed22ddeeedddcde0edddde0eeeeeeeedddddddd
-- 022:0000000000000000000220000024420000244200000220000000000000000000
-- 023:000000000c0c0c00c2c2c2c02222222c22c2c222222222200300030033003300
-- 024:0000000000c0c0c00c2c2c2cc222222222c2c222022222220030003000330033
-- 032:00444400044444404443c4444434c4444434c4444443c4440444444000444400
-- 033:00044000004444000443c4400434c4400434c4400443c4400044440000044000
-- 034:00044000000440000004c0000004c0000004c0000004c0000004400000044000
-- 035:0004400000444400044c3440044c4340044c4340044c34400044440000044000
-- 036:0000000000bbbb000bcbbab0bccbbaab0bbbaab000baab00000ab00000000000
-- 037:00000000022002202c2222222222222222222222022222200022220000022000
-- 038:000000c000000cc00000ccd0000ccd0000ccd0000cdd00000d000000d0000000
-- 039:0000000000999900009aa900009aa900009aa99909aaaaa9099999990ccccccc
-- 040:00044000000440004444444404444440004f4f00044444400440044040000004
-- 041:0d0000000d0000000d0000000d0000000d2200000d2220000d220000eeee0000
-- 042:0d0000000d5500000d5550000d5500000d0000000d0000000d000000eeee0000
-- 096:00000000022022002c2222202222222002222200002220000002000000000000
-- 097:000000000ee0ee00e00e00e0e00000e00e000e0000e0e000000e000000000000
-- 098:0000000000444000044c4400043c4400043c4400044c44000044400000000000
-- 099:0000000000bbb0000bcbab000bbaab0000bab000000b00000000000000000000
-- 100:0000000000000c000000cd00000cd00000cd00000dd000000d00000000000000
-- 101:0000000000990000009a9000009a999009aaaa90099999900cccccc000000000
-- 102:0000000000040000004440004444444004444400044044000400040000000000
-- 103:00050000005500000666666066644f4666644446066666600000000000000000
-- </SPRITES>

-- <MAP>
-- 001:0000000000000000000000000000000000000000000000000000000000000000d1e1f10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d1e1f10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:0000000000d1e1f100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d1e1f1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:000000000000000000000000000000000000000000d1e1e1f10000000000000000000000000000000000000000000000d1e1f100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d1e1f10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000013000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:000000000000000000000000000000130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 008:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:000000000000000000000000000003030300000000000000000000000000000000000000000000000000000000000000000000006300000000000000000000000000000000000000730000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001114100000000000000000000000000000000000000000000001020203000000000000000000000000000000000000000000021000000000000130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:000000000000000000000000001020202030000000000000000000000000000000000000030303000000000000000000000000000000000000000000000000000000000000004050506000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000102020205050506000000000000000000000000303030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:00230000002200008100910000000000000000a1000000000003030300000000810000000000000000005300000000000091000000d0d00000a1000000330000000040505050505050600000005300008100000000000000c100000000a10000000000530000000000000000830000009100000000008100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 014:202020202020202020202020202020202020202020202020202020202020202020202030000000102020202020202020202020202020202020202020202020202020505050505050505020202020202020202020202020202020202020202020202020300000000000102020202020202020202020202020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:505050505050505050505050505050505050505050505050505050505050505050505060000000405050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050600000000000405050505050505050505050505050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:505050505050505050505050505050505050505050505050505050505050505050505060000000405050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050600000000000405050505050505050505050505050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <WAVES>
-- 001:ffffffffffffffff0000000000000000
-- 002:ffffffff000000000000000000000000
-- 003:ffff0000000000000000000000000000
-- 004:02468acefffffffffedcba9876543210
-- 005:00112233445566778899aabbccddeeff
-- 006:89acdeefffeedca98653211000112356
-- </WAVES>

-- <SFX>
-- 000:32004210522062306240725082609270a280b290c2a0c2b0d2c0e2c0f2c0f2c0f2c0f2c0f2c0f2c0f2c0f2c0f2c0f2c0f2c0f2c0f2c0f2c0f2c0f2c0419000000000
-- 001:23002300230023002350335043504350535063507350835093509350a350b350c350d350d350e350f350f350f350f350f350f350f350f350f350f35050b000000000
-- 002:00c020904160613071009100b100d100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100310000000000
-- 003:15c015a4158c156c254c352c350c450c550c650c650c750c850c950ca50ca50cb50cc50cd50cd50ce50cf50cf50cf50cf50cf50cf50cf50cf50cf50c404000000003
-- 004:32003240327032c032003240327032c032203250329032e03240327032b032f032f032f032f032f032f042f062f072f082f0a2f0b2f0c2f0e2f0f2f0570000000000
-- 005:2100410061009100b100d100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100217000000000
-- 006:3100412051405170619071c071e081f091f0a1f0b1f0b1f0c1f0d1f0d1f0e1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0410000000000
-- 007:400060008000b000d000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000710000000000
-- 008:0070105031305100610071009100a100c100e100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100300000000000
-- 009:0000000000000000100010002000300030004000400050006000600070007000800090009000a000b000b000c000d000d000e000e000f000f000f000260000000000
-- 010:24002400240024702470247024c024c024c034c044c054c064c074c084c094c094c0a4c0b4c0c4c0d4c0e4c0f4c0f4c0f4c0f4c0f4c0f4c0f4c0f4c0500000000000
-- 011:3200320032003200323032303230323032c032c032c032c0328032803280328032a032a032a032a032f032f032f032f032f052f082f0a2f0d2f0f2f0504000000000
-- 012:330043c0437053c0534063c0737073c083c083c093c0a3c0a3c0b3c0b3c0c3c0d3c0d3c0e3c0e3c0f3c0f3c0f3c0f3c0f3c0f3c0f3c0f3c0f3c0f3c0604000000800
-- 013:52007200a200d200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200519000000000
-- 014:31f031e031d031c031b031a03190318031703160315031403130312031103100310031003100310031004100610071008100a100b100c100e100f100460000000000
-- 016:320042005200620062007200720072007200720072007200720072007200720072007200720072007200720072007200720072007200720072007200400000000000
-- 017:140024003400340044004400440044004400440044004400440044004400440044004400440044004400440044004400440044004400440044004400400000000000
-- 018:11c0317061308100a100d100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100410000000000
-- 019:4000600080009000b000d000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000400000000000
-- 020:a000d000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000400000000000
-- 021:960086007600760086008600960096009600960096009600960096009600960096009600960096009600960096009600960096009600960096009600400000000000
-- 022:410051016100710f710f810f810f810f810f810f810f810f810f810f810f810f810f810f810f810f810f810f810f810f810f810f810f810f810f810f400000000004
-- 023:240034004400540064007400840094009400a400b400c400d400e400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400400000000000
-- </SFX>

-- <PATTERNS>
-- 000:80000b000000b0000b00000040000d000000000000000000f0000b000000b0000b00000080000b000000000000000000d0000b000000000000000000b0000b00000080000b00000040000b00000000000000000080000b00000000000000000090000b000000d0000b00000040000d000000d0000b000000b0000b00000090000b00000080000b00000000000000000060000b00000080000b00000090000b000000b0000b000000000000000000000000000000f00009000000000000000000
-- 001:80000b000000b0000b00000040000d00000000000000000060000d00000040000d000000f0000b000000b0000b000000d0000b00000000000000000040000d000000d0000b00000080000b00000000000000000000000000000000000000000090000b000000d0000b00000040000d000000000000000000f0000b00000000000000000060000d00000000000000000040000d000000000000000000b0000b00000080000b00000040000b000000000000000000000000000000100000000000
-- 002:400017000000000000000000400019000000000000000000b00017000000000000000000400019000000000000000000d00015000000000000000000d00017000000000000000000800017000000000000000000d00017000000000000000000900015000000000000000000900017000000000000000000400017000000000000000000900017000000000000000000b00015000000000000000000b00017000000000000000000600017000000000000000000b00017000000000000000000
-- 003:400017000000000000000000400019000000000000000000b00017000000000000000000400019000000000000000000d00015000000000000000000d00017000000000000000000800017000000000000000000d00017000000000000000000900015000000000000000000900017000000000000000000b00015000000000000000000b00017000000000000000000400017000000000000000000400019000000000000000000b00015000000000000000000400017000000000000000000
-- 004:400027000000d0004f00000040003d000000d0004f000000400027000000d0004f00000040003d000000d0004f000000400027000000d0004f00000040003d000000d0004f000000400027000000d0004f00000040003d000000d0004f000000400027000000d0004f00000040003d000000d0004f000000400027000000d0004f00000040003d000000d0004f000000400027000000d0004f00000040003d000000d0004f00000040002700000040003d40003d40003d00000040003d000000
-- 005:d0006900000000000000000000000000000040006b00000080006b00000000000000000000000000000060006b00000040006b000000000000000000000000000000000000000000d00069000000000000000000000000000000000000000000b00069000000000000000000f0006900000000000000000060006b00000000000000000040006b000000f00069000000800069000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000
-- 006:d00015000000000000000000d00015000000000000000000d00015000000000000000000d00015000000b00015000000900015000000000000000000900015000000000000000000900015000000000000000000900015000000800015000000b00015000000000000000000b00015000000000000000000b00015000000000000000000b00015000000000000000000800015000000000000000000800015000000000000000000800015000000000000000000c00015000000000000000000
-- 007:40002700000000000000000000000000000000000000000040003d00000000000000000000000000000000000000000040002700000000000000000000000000000000000000000040003d000000000000000000000000000000d0004f00000040002700000000000000000000000000000000000000000040003d00000000000000000000000000000000000000000040002700000000000000000000000000000040002700000040003d00000000000000000040003d000000000000000000
-- 008:80006b00000080006b000000b0006b00000080006b000000d0006b000000b0006b000000a0006b00000080006b000000f0006b000000000000000000d0006b000000b0006b000000a0006b00000000000000000060006b00000000000000000080006b00000080006b000000b0006b00000080006b000000d0006b000000f0006b00000040006d000000f0006b000000d0006b000000b0006b000000a0006b00000070006b00000080006b000000000000000000000000000000000000000000
-- 009:800015000000800017000000800015000000800017000000800015000000800017000000800015000000800017000000400017000000400019000000400017000000400019000000600017000000600019000000600017000000600019000000800015000000800017000000800015000000800017000000800015000000800017000000800015000000800017000000f00015000000f00017000000f00015000000f00017000000800015000000800017000000800015000000800017000000
-- 010:400027000000d0004f40002740003d000000d0004f000000400027000000d0004f40002740003d000000d0004f000000400027000000d0004f40002740003d000000d0004f000000400027000000d0004f40002740003d00000040003d40003d400027000000d0004f40002740003d000000d0004f000000400027000000d0004f40002740003d000000d0004f000000400027000000d0004f40002740003d00000040003d00000040002740002740003d00000040003d40003d40003d40003d
-- 011:40007b00000080007b000000b0007b00000040007d000000000000000000b0007b00000080007b000000000000000000d0007900000040007b00000080007b000000d0007b00000000000000000080007b00000040007b000000000000000000900079000000d0007900000040007b00000090007b00000000000000000040007b000000d00079000000000000000000b00079000000f0007900000060007b000000b0007b00000000000000000090007b00000060007b000000f00079000000
-- 012:400059000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d00057000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000900057000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b00057000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:b0000900000040000b00000080000b000000b0000b00000040000d000000000000000000b0000b00000040000d000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 014:400017000000000000000000000000000000000000000000b00015000000000000000000400017000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:40006b000000000000000000f00069000000000000000000e00069000000000000000000d00069000000000000000000c00069000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:400017000000000000000000000000000000000000000000900015000000000000000000000000000000000000000000400015000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 017:40000b00000040000b00000040000b00000040000b000000c00009000000000000000000e0000900000000000000000040000b000000000000000000e0000900000040000b00000000000000000000000000000000000000000000000000000080000b000000b0000b00000040000d00000080000d00000060000d00000040000d000000b0000b00000080000b00000040000d000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000
-- 018:400017000000400017000000400017000000400017000000c00015000000000000000000e00015000000000000000000400017000000000000000000e00015000000400017000000000000000000000000000000000000000000000000000000400017000000000000000000800017000000000000000000900017000000000000000000b00017000000000000000000400017000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000
-- </PATTERNS>

-- <TRACKS>
-- 000:c430000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008d0000
-- 001:1c0500201500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:6c18000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008d0000
-- 003:982b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e10000
-- 004:ec3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200
-- 005:0540000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002e0200
-- 006:2d4000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </TRACKS>

-- <FLAGS>
-- 000:00101010101010000000000000200000111111111110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </FLAGS>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>

