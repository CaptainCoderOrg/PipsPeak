-- title:   Pip's Peak (lesson 4)
-- author:  TIC-80 Platformer Course
-- desc:    Palettes: day and night
-- script:  lua

-- == Constants ==
local BTN_LEFT = 2
local BTN_RIGHT = 3
local BTN_A = 4   -- A is the Z key
local ANIM_IDLE = {256, 257}
local ANIM_RUN = {258, 259, 260, 261}
local PALETTE_ADDR = 0x3FC0   -- 16 colors x 3 bytes (red, green, blue) in RAM

-- colors to change at night: palette index -> 0xRRGGBB
local NIGHT = {
  [10] = 0x29366f, [6] = 0x257179,
  [12] = 0xc8d8f0
}

-- == State ==
player = {
  x = 116, y = 104, flip = 0,
  moving = false
}
t = 0
night = false
day_colors = {}   -- the cart's own palette, saved in BOOT

-- == Palette ==
function get_color(i)
  local a = PALETTE_ADDR + i * 3
  return peek(a) << 16 | peek(a
      + 1) << 8 | peek(a + 2)
end

function set_color(i, rgb)
  local a = PALETTE_ADDR + i * 3
  poke(a, rgb >> 16 & 0xff)
  poke(a + 1, rgb >> 8 & 0xff)
  poke(a + 2, rgb & 0xff)
end

function apply_palette()
  for i = 0, 15 do
    set_color(i, day_colors[i])
  end
  if night then
    for i, rgb in pairs(NIGHT) do
      set_color(i, rgb)
    end
  end
end

-- == Animation ==
function anim_frame(frames, speed)
  return
    frames[(t // speed) % #frames + 1]
end

-- == Player ==
function update_player(p)
  p.moving = false
  if btn(BTN_LEFT) then
    p.x = p.x - 1
    p.flip = 1
    p.moving = true
  end
  if btn(BTN_RIGHT) then
    p.x = p.x + 1
    p.flip = 0
    p.moving = true
  end
end

function draw_player(p)
  local id
  if p.moving then
    id = anim_frame(ANIM_RUN, 6)
  else
    id = anim_frame(ANIM_IDLE, 30)
  end
  spr(id, p.x, p.y, 0, 1, p.flip)
end

-- == Game loop ==
function BOOT()
  for i = 0, 15 do
    day_colors[i] = get_color(i)
  end
end

function TIC()
  t = t + 1
  if btnp(BTN_A) then
    night = not night
    apply_palette()
  end
  update_player(player)

  cls(10)
  rect(0, 112, 240, 24, 6)
  if night then   -- moon or sun
    circ(200, 24, 8, 12)
  else
    circ(200, 24, 10, 4)
  end
  draw_player(player)
  print("Z: day/night", 4, 4, 12)
end

-- <SPRITES>
-- 000:00050000005500000666666066644f4666644446066666600660066003300330
-- 001:0000000000050000005560000666666066644f46666444460666666003300330
-- 002:00050000005500000666666066644f4666644446066666606600060030000330
-- 003:0000000000050000005560000666666066644f46666444460666666000336300
-- 004:00050000005500000666666066644f4666644446066666600060006603300003
-- 005:0000000000050000005560000666666066644f46666444460666666000363300
-- 006:00050000005500000666666066644f4666644446066666606600006630000003
-- 007:00500500000550000666666066644f4666644446066666600660066003000030
-- </SPRITES>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>

