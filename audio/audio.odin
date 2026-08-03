/* thin wrapper over miniaudio: music is one long-lived streaming handle you
   can loop / swap / stop, sfx are fire-and-forget one-shots routed through
   their own group so they share a volume knob.

   usage from main:
     audio.init()
     defer audio.shutdown()
     audio.play_music("assets/theme.wav")
     audio.play_sfx("assets/bounce.wav")
*/
package audio

import fmt "core:fmt"
import strings "core:strings"
import ma "vendor:miniaudio"

@(private)
State :: struct {
  engine:       ma.engine,
  sfx_group:    ma.sound_group,
  music:        ma.sound,
  music_loaded: bool,
}

@(private)
state: State

init :: proc() -> bool {
  if ma.engine_init(nil, &state.engine) != .SUCCESS {
    fmt.println("audio: failed to init engine")
    return false
  }

  if ma.sound_group_init(&state.engine, {}, nil, &state.sfx_group) != .SUCCESS {
    fmt.println("audio: failed to init sfx group")
    ma.engine_uninit(&state.engine)
    return false
  }

  return true
}

shutdown :: proc() {
  stop_music()
  ma.sound_group_uninit(&state.sfx_group)
  ma.engine_uninit(&state.engine)
}

/* streams music straight off disk (no full decode into ram) and loops it
   forever by default. calling it again swaps whatever was already playing */
play_music :: proc(path: string, loop := true) -> bool {
  stop_music()

  cpath := strings.clone_to_cstring(path)
  defer delete(cpath)

  if ma.sound_init_from_file(&state.engine, cpath, {.STREAM}, nil, nil, &state.music) != .SUCCESS {
    fmt.println("audio: failed to load music:", path)
    return false
  }
  state.music_loaded = true

  ma.sound_set_looping(&state.music, b32(loop))

  if ma.sound_start(&state.music) != .SUCCESS {
    fmt.println("audio: failed to play music:", path)
    stop_music()
    return false
  }

  return true
}

/* unloads the track entirely, use pause_music if you want to come back to it */
stop_music :: proc() {
  if !state.music_loaded { return }
  ma.sound_uninit(&state.music)
  state.music_loaded = false
}

pause_music :: proc() {
  if !state.music_loaded { return }
  ma.sound_stop(&state.music)
}

resume_music :: proc() {
  if !state.music_loaded { return }
  ma.sound_start(&state.music)
}

/* jump back to the top of the track */
restart_music :: proc() {
  if !state.music_loaded { return }
  ma.sound_seek_to_pcm_frame(&state.music, 0)
}

is_music_playing :: proc() -> bool {
  if !state.music_loaded { return false }
  return bool(ma.sound_is_playing(&state.music))
}

set_music_volume :: proc(volume: f32) {
  if !state.music_loaded { return }
  ma.sound_set_volume(&state.music, volume)
}

/* fire and forget: safe to call every time a paddle connects. the engine owns
   the sound and reclaims it once playback finishes */
play_sfx :: proc(path: string) -> bool {
  cpath := strings.clone_to_cstring(path)
  defer delete(cpath)

  if ma.engine_play_sound(&state.engine, cpath, &state.sfx_group) != .SUCCESS {
    fmt.println("audio: failed to play sfx:", path)
    return false
  }

  return true
}

set_sfx_volume :: proc(volume: f32) {
  ma.sound_group_set_volume(&state.sfx_group, volume)
}

/* 0.0 .. 1.0, music and sfx together */
set_master_volume :: proc(volume: f32) {
  ma.engine_set_volume(&state.engine, volume)
}
