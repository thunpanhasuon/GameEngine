package main

import "base:runtime"
import fmt "core:fmt"
import math "core:math/linalg"
import time "core:time"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import "core:math/rand"

import audio "audio"
import colors "colors"
import object "object"
import memory "memory"

error_callback :: proc "c" (code: i32, description: cstring) {
    context = runtime.default_context()
    fmt.println("GLFW Error", code, ":", description)
}

vertices := []f32{
  -0.5, -0.5, 0.0,  // bl
  0.5, -0.5, 0.0,   // br
  0.5, 0.5, 0.0,    // tr
  -0.5, 0.5, 0.0,   // tl
}
indices := [6]u32{
  0, 1, 3,
  1, 2, 3,
}

GpuData :: struct {
  vao:     u32,
  vbo:     u32,
  ebo:     u32,
  program: u32,
}
GpuVertexData :: struct {
  mvp_location: i32, 
  u_color_location: i32,
}
gpu: GpuData
gpu_vertex: GpuVertexData


/* the object package owns these now, alias them so the update procs can be
   handed the same structs main draws from */
Velocity   :: object.Velocity
Box        :: object.Box
GameObject :: object.GameObject

/* everything about frame timing lives here: call clock_tick() once per
   loop and it hands you back a ready-to-use dt, already capped at 60fps */
TARGET_FRAME_TIME :: 1.0 / 60.0
WINDOW_WIDHT :: 800
WINDOW_HEIGHT :: 600


Clock :: struct {
  last_tick: time.Tick,
}

clock_init :: proc() -> Clock {
  return Clock{ last_tick = time.tick_now() }
}

clock_tick :: proc(c: ^Clock) -> f32 {
  elapsed := time.duration_seconds(time.tick_diff(c.last_tick, time.tick_now()))
  if elapsed < TARGET_FRAME_TIME {
    time.sleep(time.Duration((TARGET_FRAME_TIME - elapsed) * f64(time.Second)))
  }

  now := time.tick_now()
  dt := f32(time.duration_seconds(time.tick_diff(c.last_tick, now)))
  c.last_tick = now
  return dt
}

/* macOS is the dev machine and i work on the move there, so there is rarely a
   controller plugged in: fall back to wasd when no stick is pushing */
when ODIN_OS == .Darwin {
  DEV_KEYBOARD :: true
} else {
  DEV_KEYBOARD :: false
}
update :: proc(o: []GameObject, dt: f32) {
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
    } else if o[i].box.x + o[i].box.w > WINDOW_WIDHT {
      o[i].box.x = WINDOW_WIDHT - o[i].box.w
      o[i].velocity.velx = -abs(o[i].velocity.velx)
    }

    if o[i].box.y < 0 {
      o[i].box.y = 0
      o[i].velocity.vely = abs(o[i].velocity.vely)
    } else if o[i].box.y + o[i].box.h > WINDOW_HEIGHT {
      o[i].box.y = WINDOW_HEIGHT - o[i].box.h
      o[i].velocity.vely = -abs(o[i].velocity.vely)
    }
  }
}
/* same shape as the gamepad axes: -1..1, y is negative going up so it matches
   the stick and the top-left origin of the ortho projection */
get_keyboard_axes :: proc(window: glfw.WindowHandle) -> (x: f32, y: f32) {
  if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS { x -= 1.0 }
  if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS { x += 1.0 }
  if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS { y -= 1.0 }
  if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS { y += 1.0 }
  return
}

get_overlap :: proc(box_a: Box, box_b: Box) -> (lapX: f32, lapY: f32) {
  over_lapx := math.min(box_a.x + box_a.w, box_b.x + box_b.w) - math.max(box_a.x, box_b.x)
  over_lapy := math.min(box_a.y + box_a.h, box_b.y + box_b.h)  - math.max(box_a.y, box_b.y)
  return over_lapx, over_lapy
}

check_collision :: proc(box_a: Box, box_b: Box) -> bool {
  return box_a.x < box_b.x + box_b.w &&
         box_a.x + box_a.w > box_b.x &&
         box_a.y < box_b.y + box_b.h &&
         box_a.y + box_a.h > box_b.y
}
find_location :: proc() {
  gpu_vertex.mvp_location = gl.GetUniformLocation(gpu.program, "mvp")
  gpu_vertex.u_color_location = gl.GetUniformLocation(gpu.program, "uColor")
}
draw_rect :: proc(x: f32, y: f32, w: f32, h: f32, color: colors.Lofi_Color) {

  /* calucated matrix model */
  model: matrix[4, 4]f32 = 1.0
  /* quad vertices are centered on the origin (-0.5..0.5), but x/y here
     is the top-left corner (matches Box / collision convention), so
     shift the pivot by half the box size */
  transation := math.matrix4_translate_f32({x + w * 0.5, y + h * 0.5, 0.0})
  scale := math.matrix4_scale_f32({w, h, 0.0})
  model = transation * scale

  /* projection */
  proj := math.matrix_ortho3d_f32(0, WINDOW_WIDHT, WINDOW_HEIGHT, 0, -1, 1)

  /* model view projection */
  mvp_matrix: matrix[4, 4]f32
  mvp_matrix = proj * model

  gl.UniformMatrix4fv(gpu_vertex.mvp_location, 1, gl.FALSE, &mvp_matrix[0, 0])
  rgba := colors.rgba(color)
  gl.Uniform4fv(gpu_vertex.u_color_location, 1, &rgba[0])
  /* one lookup, then hand the whole rgba to the shader */
  gl.BindVertexArray(gpu.vao)
  gl.DrawElements(gl.TRIANGLES, len(indices), gl.UNSIGNED_INT, nil)
}

set_gpu_data :: proc() {
  gl.GenVertexArrays(1, &gpu.vao)
  gl.GenBuffers(1, &gpu.vbo)
  gl.GenBuffers(1, &gpu.ebo)
  gl.BindVertexArray(gpu.vao)

  gl.BindBuffer(gl.ARRAY_BUFFER, gpu.vbo)
  gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(vertices[0]), raw_data(vertices), gl.STATIC_DRAW)

  gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gpu.ebo)
  gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(indices), &indices, gl.STATIC_DRAW)

  POSITION_COMPONENTS :: 3 // x, y, z
  gl.VertexAttribPointer(0, POSITION_COMPONENTS, gl.FLOAT, false, POSITION_COMPONENTS * size_of(f32), 0)
  gl.EnableVertexAttribArray(0)
}
/* Vertex input */
create_quad :: proc() {

  vertex_src := `#version 330 core
layout (location = 0) in vec3 aPos;
uniform mat4 mvp;
void main() {
    gl_Position = mvp * vec4(aPos, 1.0);
}`

fragment_src := `#version 330 core
uniform vec4 uColor; 
out vec4 FragColor;
void main() {
    FragColor = uColor; // pinkish, tweak to taste
}`

  ok: bool
  gpu.program, ok = gl.load_shaders_source(vertex_src, fragment_src)

  if !ok {
    fmt.println("shader compile failed")
  }
  fmt.println("shader program:", gpu.program, "ok:", ok)

}

game_engine_start :: proc() {
  set_gpu_data()
  create_quad()
  find_location()
  gl.UseProgram(gpu.program)
}

main :: proc() {

  glfw.SetErrorCallback(error_callback)
  glfw.Init();
  defer glfw.Terminate()

  glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
  glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
  glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

  window := glfw.CreateWindow(800, 600, "Odin Engine", nil, nil)


  if window == nil {
    fmt.println("fail to create window");
    glfw.Terminate()
    return
  }
  defer glfw.DestroyWindow(window)

  glfw.MakeContextCurrent(window)
  gl.load_up_to(3,3, glfw.gl_set_proc_address)

  /* start the game engine */
  game_engine_start()
  /* start the game audio */
  if !audio.init() {
    return
  }
  defer audio.shutdown()

  /* paths are relative to the working dir, so run the exe from the repo root */
  audio.play_music("music/aura.mp3")   // loops until stop_music()
  audio.set_music_volume(0.5)

  /* boxes spawn in a grid sized to the window, so the layout holds for any
     ENTITY_COUNT -- crank it for a stress test and nothing lands off-screen.
     a single row stopped fitting past ~13 boxes. */
  ENTITY_COUNT :: 30000
  ENTITY_FILL  :: f32(0.85)  // share of its cell a box fills; the rest is the gap
  ENTITY_SPEED :: f32(300.0)

  /* whichever column count gives the largest cell for this window shape.
     cheap to brute force: it runs once, at startup */
  cols := 1
  best_cell := f32(0)
  for c in 1..=ENTITY_COUNT {
    r := (ENTITY_COUNT + c - 1) / c
    cell := min(f32(WINDOW_WIDHT) / f32(c), f32(WINDOW_HEIGHT) / f32(r))
    if cell > best_cell {
      best_cell = cell
      cols = c
    }
  }
  rows := (ENTITY_COUNT + cols - 1) / cols

  /* floor at 1px: past ~480k boxes a cell is thinner than a pixel */
  size := max(best_cell * ENTITY_FILL, 1.0)
  /* centre the grid, then centre each box inside its own cell */
  origin_x := (f32(WINDOW_WIDHT) - f32(cols) * best_cell) * 0.5
  origin_y := (f32(WINDOW_HEIGHT) - f32(rows) * best_cell) * 0.5
  inset    := (best_cell - size) * 0.5

  entities := memory.memory_init(ENTITY_COUNT)
  /* the arena is one fixed buffer, so a big enough ENTITY_COUNT just fails the
     allocation and hands back an empty slice. say so, rather than letting the
     first index trip the bounds check */
  if len(entities) != ENTITY_COUNT {
    fmt.println("entity alloc failed: arena fits", len(memory.buf) / size_of(GameObject), "objects, asked for", ENTITY_COUNT)
    return
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
  clock := clock_init()
  for !glfw.WindowShouldClose(window) {
   /* dt is already capped at 60fps by the time you get it */
   dt := clock_tick(&clock)

   glfw.PollEvents()

   lx, ly: f32

   if glfw.JoystickIsGamepad(glfw.JOYSTICK_1) {

     deadzone: f32 = 0.15

     state: glfw.GamepadState
     glfw.GetGamepadState(glfw.JOYSTICK_1, &state)

     lx = state.axes[glfw.GAMEPAD_AXIS_RIGHT_X]
     ly = state.axes[glfw.GAMEPAD_AXIS_RIGHT_Y]

     /* provent stick drift */
     if abs(lx) < deadzone { lx = 0.0 }
     if abs(ly) < deadzone { ly = 0.0 }
   }

   /* no stick input (or no controller at all) -> keyboard takes over */
   when DEV_KEYBOARD {
     if lx == 0.0 && ly == 0.0 {
       lx, ly = get_keyboard_axes(window)
     }
   }

   /* gameplay update goes here — lx / ly are the movement axes for the frame */
   update(entities, dt)
   /* background comes out of the same palette, so nothing can drift apart */
   bg := colors.rgba(.Cream)
   gl.ClearColor(bg[0], bg[1], bg[2], bg[3])
   gl.Clear(gl.COLOR_BUFFER_BIT)
  
   for i in 0..<ENTITY_COUNT {
      draw_rect(entities[i].box.x, entities[i].box.y, entities[i].box.w, entities[i].box.h, .Mocha)
   }
   glfw.SwapBuffers(window)

   /* loop timing / fps */
   fmt.println("frame time:", dt * 1000.0, "ms | fps:", 1.0 / dt)
  }
  memory.memory_free()
}
