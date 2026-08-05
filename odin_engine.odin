package main

import "base:runtime"
import fmt "core:fmt"
import math "core:math/linalg"
import time "core:time"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"

import audio "audio"
import colors "colors"
import object "object"
import renderer "renderer"

error_callback :: proc "c" (code: i32, description: cstring) {
    context = runtime.default_context()
    fmt.println("GLFW Error", code, ":", description)
}

/* the object package owns this now, alias it so the collision helpers below
   can be handed the same struct main draws from */
Box :: object.Box

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
  renderer.init(WINDOW_WIDHT, WINDOW_HEIGHT)
  /* start the game audio */
  if !audio.init() {
    return
  }
  defer audio.shutdown()

  /* paths are relative to the working dir, so run the exe from the repo root */
  audio.play_music("../game/engine/game_audio.mp3")   // loops until stop_music()
  audio.set_music_volume(0.5)

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

   /* update */

   /* background comes out of the same palette, so nothing can drift apart */
   bg := colors.rgba(.Charcoal)
   gl.ClearColor(bg[0], bg[1], bg[2], bg[3])
   gl.Clear(gl.COLOR_BUFFER_BIT)

   /* render */

   glfw.SwapBuffers(window)

   /* loop timing / fps */
   fmt.println("frame time:", dt * 1000.0, "ms | fps:", 1.0 / dt)
  }
}
