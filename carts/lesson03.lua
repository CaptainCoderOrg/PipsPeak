-- title:   Pip's Peak (lesson 3)
-- author:  TIC-80 Platformer Course
-- desc:    Animation: making Pip walk
-- script:  lua

-- == Constants ==
local BTN_LEFT, BTN_RIGHT = 2, 3     -- 0 is up, 1 is down
-- animations are lists of sprite ids
local ANIM_IDLE = {256, 257}
local ANIM_RUN = {258, 259, 260, 261}

-- == State ==
player = {
  x = 116, y = 104, flip = 0,
  moving = false
}
t = 0   -- frame counter: animations use it as their clock

-- == Animation ==
-- The sprite to show now for an animation that changes every `speed` frames.
function anim_frame(frames, speed)
  return
    frames[(t // speed) % #frames + 1]
end

-- == Player ==
function update_player(p)
  p.moving = false
  if btn(BTN_LEFT) then
    p.x = p.x - 1
    p.flip = 1          -- the sprites face right; flip them to face left
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
function TIC()
  t = t + 1
  update_player(player)

  cls(10)
  rect(0, 112, 240, 24, 6)
  draw_player(player)
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

