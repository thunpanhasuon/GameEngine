package object

/* shared game object data. anything with a position, a size or a speed uses
   these types so gameplay, rendering and collision all agree on one layout.

   convention (matches the renderer and the ortho projection): x/y is the
   top-left corner, y grows downwards. */

Velocity :: struct {
  velx, vely: f32,
}

Box :: struct {
  x, y, w, h: f32,
}

GameObject :: struct {
  id: i32,
  box:      Box,
  velocity: Velocity,
}

