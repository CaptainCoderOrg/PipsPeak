-- title:   Pip's Peak (lesson 5)
-- author:  TIC-80 Platformer Course
-- desc:    Gravity and jumping
-- script:  lua

-- == Constants ==
local BTN_LEFT = 2
local BTN_RIGHT = 3
local BTN_A = 4   -- A is the Z key
local ANIM_IDLE = {256, 257}
local ANIM_RUN = {258, 259, 260, 261}
local SPR_JUMP, SPR_FALL = 262, 263

local GROUND_Y = 104    -- Pip stands here (the grass starts at y = 112)
local GRAVITY = 0.25    -- added to vy every frame (pixels per frame per frame)
local JUMP_SPEED = -4   -- vy when a jump starts (negative is up)
local JUMP_CUT = -1.5   -- releasing the button early caps vy here
local MAX_FALL = 4      -- the fastest Pip can fall

-- == State ==
player = {
  x = 116, y = GROUND_Y, vy = 0,
  flip = 0, moving = false,
  ground = true, jumping = false
}
t = 0

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

  -- jump: btnp is true only on the frame the button goes down
  if btnp(BTN_A) and p.ground then
    p.vy = JUMP_SPEED
    p.ground = false
    p.jumping = true
  end
  -- let go early for a short hop (only a jump Pip started can be cut short)
  if p.jumping and not btn(BTN_A)
      and p.vy < JUMP_CUT then
    p.vy = JUMP_CUT
  end
  if p.vy >= 0 then
    p.jumping = false
  end

  -- gravity speeds the fall up, every frame
  p.vy =
    math.min(p.vy + GRAVITY, MAX_FALL)
  p.y = p.y + p.vy

  -- land on the ground
  if p.y >= GROUND_Y then
    p.y = GROUND_Y
    p.vy = 0
    p.ground = true
  end
end

function draw_player(p)
  local id
  if not p.ground then
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

