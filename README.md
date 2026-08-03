# consoleEngine

A small 2D game engine written in [Odin](https://odin-lang.org), using OpenGL 3.3 for rendering, GLFW for windowing and input, and miniaudio for sound. The engine currently ships with a playable Pong: you against an AI paddle, gamepad or keyboard, with music and sfx.

## Requirements

- [Odin compiler](https://odin-lang.org/docs/install/) (tested with `dev-2026-06`)
- OpenGL 3.3 capable GPU
- macOS, Linux or Windows (GLFW and miniaudio ship with Odin's `vendor` collection)

## Run

Paths to audio files are relative to the working directory, so run from the repo root:

```sh
odin run .
```

To build a binary instead:

```sh
odin build .
./consoleEngine
```

## Controls

| Input | Action |
| --- | --- |
| Right stick (gamepad) | Move the left paddle |
| `W` / `S` | Move the left paddle (macOS dev fallback) |
| `A` / `D` | Horizontal axis, currently unused by Pong |

The keyboard fallback is compiled in only on macOS (`DEV_KEYBOARD`), and only takes over when the stick is idle. Gamepad input always wins when a controller is pushing.

## Layout

```
odin_engine.odin   window, GL setup, quad renderer, frame clock, main loop
game/pong.odin     game package: physics structs, ball, player and AI paddles
audio/audio.odin   audio package: miniaudio wrapper for music and sfx
music/             looping background tracks (.wav)  — not in the repo
sounds/            one-shot sound effects (.wav)     — not in the repo
```

`music/` and `sounds/` hold licensed third-party audio and are gitignored, so they are not distributed with the source. Supply your own `.wav` files in those folders, or point the paths in [odin_engine.odin](odin_engine.odin) and the `SFX_*` constants in [game/pong.odin](game/pong.odin) at wherever your assets live.

## Engine pieces

**Frame clock** — `clock_tick()` sleeps out the remainder of the frame and hands back a `dt` already capped at 60 fps, so the whole loop is one call away from correct timing.

**Renderer** — a single unit quad (VAO/VBO/EBO) plus a minimal shader pair. `draw_rect(x, y, w, h)` builds an MVP from an orthographic projection sized to the window and issues one draw call. The projection has its origin at the top-left, and `x, y` is the top-left corner of the rect, so it matches the `Box` collision convention.

**Physics** — `Box` (x, y, w, h) and `Velocity` (velx, vely) combine into `Physic`. Collision is a plain AABB overlap test; `get_overlap` returns the penetration on each axis for resolution.

**Audio** — `audio.init()` / `audio.shutdown()` bracket the engine. Music is one long-lived streaming handle you can loop, swap, pause or restart; sfx are fire-and-forget one-shots routed through their own group so they share a volume knob.

```odin
audio.play_music("music/journey_begins.wav")  // loops until stop_music()
audio.set_music_volume(0.5)
audio.play_sfx("sounds/cursor_1_square.wav")
```

## Pong AI

The opponent paddle is tuned through three constants in [game/pong.odin](game/pong.odin):

| Constant | Meaning |
| --- | --- |
| `AI_REACT_DIST` | How close the ball must be before the AI starts tracking it. A paddle that tracks from across the field never loses. |
| `AI_AIM_BIAS` | Fraction of the paddle's half-height it deliberately misaims by, so returns come off the edge and rallies stay interesting. |
| `AI_DEADZONE` | Pixels of slop before it bothers moving, which keeps it from vibrating. |

`predict_ball_y` folds the ball's free-flight path back into the field with a triangle wave, so the AI aims at where the ball will actually be after its wall bounces rather than where it is now.
