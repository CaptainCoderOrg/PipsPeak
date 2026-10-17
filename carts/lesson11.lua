-- title:   Pip's Peak (lesson 11)
-- author:  TIC-80 Platformer Course
-- desc:    Collectibles, entities and the HUD
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
local ANIM_COIN = {288, 289, 290, 291}
local SPR_GEM = 292
local SPR_HUD_COIN = 354
local SPR_HUD_GEM = 355

local F_SOLID = 0       -- sprite flag 0 marks tiles you can stand on
local M_START = 50      -- marker tiles: where Pip starts the level,
local M_COIN, M_GEM = 48, 49   -- and where the coins and gems are

-- Each level is a rectangle of the map, in cells.
local LEVELS = {
  {
    name = "GREEN MEADOW", x = 0,
    y = 0, w = 120, h = 17, sky = 10
  },
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
  coyote = 0, buffer = 0, squash = 0
}
t = 0
cam = {x = 0, y = 0}   -- the top-left corner of the screen, in level pixels
state = "title"        -- "title" or "play"
level = 1              -- which level we're on
lvl = LEVELS[1]        -- that level's table
start_x, start_y = 0, 0
level_t = 0            -- frames since the level started
score, coins, gems = 0, 0, 0
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

function update_pickup(e)
  if overlaps(player, e) then
    e.dead = true
    if e.kind == "coin" then
      coins = coins + 1
      score = score + 10
      burst(e.x + 3, e.y + 3, 6, 4)
    else
      gems = gems + 1
      score = score + 500
      burst(e.x + 3, e.y + 3, 12, 11)
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

-- == HUD ==
function draw_hud()
  rect(0, 0, 240, 9, 0)
  print(string.format("%06d", score),
      4, 2, 12, true)
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
    p.vx = approach(p.vx,
        dir * P.run_speed, p.ground
        and P.accel or P.air_accel)
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
  if p.buffer > 0
      and p.coyote > 0 then
    p.vy = P.jump_speed
    p.jumping = true
    p.buffer, p.coyote = 0, 0
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
  if move_y(p, p.vy) then p.vy = 0 end
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

  -- fell below the level: start again
  if p.y > (lvl.y + lvl.h) * 8 then
    reset_player()
  end
end

function draw_player(p)
  local id
  if p.squash > 0 then
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
  -- everything in the level is drawn relative to the camera
  spr(id, p.x - 1 - cam.x,
      p.y - cam.y, 0, 1, p.flip)
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
}

function reset_player()
  local p = player
  p.x, p.y, p.vx, p.vy =
    start_x, start_y, 0, 0
  p.flip, p.squash, p.coyote,
    p.buffer = 0, 0, 0, 0
end

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
function update_title()
  if btnp(BTN_A) then
    score, coins, gems = 0, 0, 0
    load_level(1)
    state = "play"
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
function TIC()
  t = t + 1
  if state == "title" then
    update_title()
    draw_title()
  elseif state == "play" then
    update_play()
    draw_play()
  end
end

-- <TILES>
-- 001:0555555655656565566666666266662611222222122321221122223212212222
-- 002:5565556556565656666666662666266622222222222321221222223222212222
-- 003:6555555056565655666666656266662622222211222321211222223122212221
-- 004:1222222212232122122222321221222212222322132222121222222211221222
-- 005:2222222222232122122222322221222222222322232222122222222222122212
-- 006:2222222122232121122222312221222122222321232222112222222122122111
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
-- 009:0000000000000000000500000055000066666666666644f66666666633000033
-- 032:00444400044444404443c4444434c4444434c4444443c4440444444000444400
-- 033:00044000004444000443c4400434c4400434c4400443c4400044440000044000
-- 034:00044000000440000004c0000004c0000004c0000004c0000004400000044000
-- 035:0004400000444400044c3440044c4340044c4340044c34400044440000044000
-- 036:0000000000bbbb000bcbbab0bccbbaab0bbbaab000baab00000ab00000000000
-- 098:0000000000444000044c4400043c4400043c4400044c44000044400000000000
-- 099:0000000000bbb0000bcbab000bbaab0000bab000000b00000000000000000000
-- </SPRITES>

-- <MAP>
-- 001:0000000000000000000000000000000000000000000000000000000000000000d1e1f10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d1e1f10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:0000000000d1e1f100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d1e1f1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:000000000000000000000000000000000000000000d1e1e1f10000000000000000000000000000000000000000000000d1e1f100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d1e1f10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000013000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:000000000000000000000000000000130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 008:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:000000000000000000000000000003030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001020203000000000000000000000000000000000000000000000000000000000130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:000000000000000000000000001020202030000000000000000000000000000000000000030303000000000000000000000000000000000000000000000000000000000000004050506000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000102020205050506000000000000000000000000303030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:00230000002200008100910000000000000000a100000000000303030000000081000000000000000000000000000000009100000000000000a1000000000000000040505050505050600000000000008100000000000000c100000000a10000000000000000000000000000000000009100000000008100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 014:202020202020202020202020202020202020202020202020202020202020202020202030000000102020202020202020202020202020202020202020202020202020505050505050505020202020202020202020202020202020202020202020202020300000000000102020202020202020202020202020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:505050505050505050505050505050505050505050505050505050505050505050505060000000405050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050600000000000405050505050505050505050505050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:505050505050505050505050505050505050505050505050505050505050505050505060000000405050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050505050600000000000405050505050505050505050505050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <FLAGS>
-- 000:00101010101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </FLAGS>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>

