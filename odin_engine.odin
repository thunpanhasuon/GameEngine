package main

import "base:runtime"
import fmt "core:fmt"
import math "core:math/linalg"
import time "core:time"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"

import audio "audio"
import game "game"

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

gpu: GpuData


/* the game package owns these now, alias them so the update procs can be
   handed the same structs main draws from */
Velocity :: game.Velocity
Box      :: game.Box
Physic   :: game.Physic

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

draw_rect :: proc(x: f32, y: f32, w: f32, h: f32) {
  /* location for mvp */
  mvp_location := gl.GetUniformLocation(gpu.program, "mvp")

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

  gl.UseProgram(gpu.program)

  gl.UniformMatrix4fv(mvp_location, 1, gl.FALSE, &mvp_matrix[0, 0])


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
out vec4 FragColor;
void main() {
    FragColor = vec4(1.0, 0.5, 0.6, 1.0); // pinkish, tweak to taste
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
  audio.play_music("music/journey_begins.wav")   // loops until stop_music()
  audio.set_music_volume(0.5)


   paddle1 := Physic{
    /* box player */
    Box{50, 200.0, 30, 200},
    /* player speed */
    Velocity{300.0, 300.0},
  }
   paddle2 := Physic{
    /* box player */
    Box{WINDOW_WIDHT - (50 + 50), 200.0, 30, 200},
    /* player speed */
    Velocity{300.0, 300.0},
  }
  
  ball := Physic{
    Box{WINDOW_WIDHT / 2.0, WINDOW_HEIGHT / 2.0, 30, 30},
    /* player speed */
    Velocity{200.0, 200.0},
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

   /* gameplay: player paddle follows the stick / wasd, ai chases the ball,
      ball resolves collisions and fires the sfx */
   game.update_player(&paddle1, ly, dt)
   game.update_ai(&paddle2, &ball, dt)
   game.update_ball(&ball, &paddle1, &paddle2, dt)

   gl.ClearColor(0.94, 0.87, 0.78, 1.0)
   gl.Clear(gl.COLOR_BUFFER_BIT)

   draw_rect(paddle1.box.x, paddle1.box.y, paddle1.box.w, paddle1.box.h)
   draw_rect(paddle2.box.x, paddle2.box.y, paddle2.box.w, paddle2.box.h)
   draw_rect(ball.box.x, ball.box.y, ball.box.w, ball.box.h)

   glfw.SwapBuffers(window)

   /* loop timing / fps */
   //fmt.println("frame time:", dt * 1000.0, "ms | fps:", 1.0 / dt)
  }
}
