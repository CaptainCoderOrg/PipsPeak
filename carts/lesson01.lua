-- title:   Pip's Peak (lesson 1)
-- author:  TIC-80 Platformer Course
-- desc:    Meet TIC-80: the game loop
-- script:  lua

-- == State ==
-- Variables declared up here (without `local`) are globals: they keep
-- their value from one frame to the next.
x = 120
y = 60
t = 0

-- == Game loop ==
-- TIC-80 calls TIC() 60 times every second. Each call is one frame:
-- read the buttons, update the state, then draw everything again.
function TIC()
  t = t + 1

  -- the arrow keys are buttons 0 (up), 1 (down), 2 (left) and 3 (right)
  if btn(0) then y = y - 1 end
  if btn(1) then y = y + 1 end
  if btn(2) then x = x - 1 end
  if btn(3) then x = x + 1 end

  cls(10)                        -- clear the screen to color 10 (sky blue)
  rect(0, 112, 240, 24, 6)       -- grass: x, y, width, height, color
  circ(x, y, 6, 4)               -- a yellow ball: center x, y, radius, color
  print("HELLO, TIC-80!", 78, 20, 12)
  print("frame " .. t, 4, 4, 0)
end

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>

