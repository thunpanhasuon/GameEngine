package test

import fmt "core:fmt"
import rand "core:math/rand"

import memory "../memory"
import object "../object"
import renderer "../renderer"

GameObject :: object.GameObject

/* boxes spawn in a grid sized to the window, so the layout holds for any
   ENTITY_COUNT -- crank it for a stress test and nothing lands off-screen.
   a single row stopped fitting past ~13 boxes. */
ENTITY_COUNT :: 30000
ENTITY_FILL  :: f32(0.85)  // share of its cell a box fills; the rest is the gap
ENTITY_SPEED :: f32(300.0)

init :: proc(width: f32, height: f32) -> []GameObject {
  /* whichever column count gives the largest cell for this window shape.
     cheap to brute force: it runs once, at startup */
  cols := 1
  best_cell := f32(0)
  for c in 1..=ENTITY_COUNT {
    r := (ENTITY_COUNT + c - 1) / c
    cell := min(width / f32(c), height / f32(r))
    if cell > best_cell {
      best_cell = cell
      cols = c
    }
  }
  rows := (ENTITY_COUNT + cols - 1) / cols

  /* floor at 1px: past ~480k boxes a cell is thinner than a pixel */
  size := max(best_cell * ENTITY_FILL, 1.0)
  /* centre the grid, then centre each box inside its own cell */
  origin_x := (width - f32(cols) * best_cell) * 0.5
  origin_y := (height - f32(rows) * best_cell) * 0.5
  inset    := (best_cell - size) * 0.5

  entities := memory.memory_init(ENTITY_COUNT)
  /* the arena is one fixed buffer, so a big enough ENTITY_COUNT just fails the
     allocation and hands back an empty slice. say so, rather than letting the
     first index trip the bounds check */
  if len(entities) != ENTITY_COUNT {
    fmt.println("entity alloc failed: arena fits", len(memory.buf) / size_of(GameObject), "objects, asked for", ENTITY_COUNT)
    return entities
  }
  for i in 0..<ENTITY_COUNT {
    entities[i].id = i32(i)
    entities[i].box.x = origin_x + f32(i % cols) * best_cell + inset
    entities[i].box.y = origin_y + f32(i / cols) * best_cell + inset
    entities[i].box.w = size
    entities[i].box.h = size
    /* roll the direction once, here. rolling it per frame in update() is what
       made the row jitter in lockstep instead of travelling */
    entities[i].velocity.velx = ENTITY_SPEED * rand.choice([]f32{-1, 1})
    entities[i].velocity.vely = ENTITY_SPEED * rand.choice([]f32{-1, 1})
  }
  return entities
}

update :: proc(o: []GameObject, dt: f32, width: f32, height: f32) {
  for i in 0..<len(o) {
    o[i].box.x += o[i].velocity.velx * dt
    o[i].box.y += o[i].velocity.vely * dt

    /* clamp back onto the wall before picking the new direction. flipping the
       sign alone leaves the box out of bounds, so the test fires again next
       frame and turns it straight back into the wall -- that is the stutter.
       abs / -abs instead of *= -1 keeps it idempotent: even a double trigger
       ends up pointing inwards. */
    if o[i].box.x < 0 {
      o[i].box.x = 0
      o[i].velocity.velx = abs(o[i].velocity.velx)
    } else if o[i].box.x + o[i].box.w > width {
      o[i].box.x = width - o[i].box.w
      o[i].velocity.velx = -abs(o[i].velocity.velx)
    }

    if o[i].box.y < 0 {
      o[i].box.y = 0
      o[i].velocity.vely = abs(o[i].velocity.vely)
    } else if o[i].box.y + o[i].box.h > height {
      o[i].box.y = height - o[i].box.h
      o[i].velocity.vely = -abs(o[i].velocity.vely)
    }
  }
}

draw :: proc(o: []GameObject) {
  for i in 0..<len(o) {
    renderer.draw_rect(o[i].box.x, o[i].box.y, o[i].box.w, o[i].box.h, .Mocha)
  }
}
