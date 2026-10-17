-- title:   Pip's Peak (lesson 2)
-- author:  TIC-80 Platformer Course
-- desc:    The sprite editor: drawing Pip
-- script:  lua

-- == Constants ==
-- TIC-80 has no names for its buttons, so we make our own.
local BTN_LEFT, BTN_RIGHT = 2, 3     -- 0 is up, 1 is down
local PIP = 256          -- sprite 256 is the first one on the SPRITES tab

-- == State ==
player = {x = 116, y = 104}

-- == Game loop ==
function TIC()
  if btn(BTN_LEFT) then
    player.x = player.x - 1
  end
  if btn(BTN_RIGHT) then
    player.x = player.x + 1
  end

  cls(10)
  rect(0, 112, 240, 24, 6)
  -- spr(id, x, y, colorkey): pixels of the colorkey color are see-through
  spr(PIP, player.x, player.y, 0)
end

-- <SPRITES>
-- 000:00050000005500000666666066644f4666644446066666600660066003300330
-- </SPRITES>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>

