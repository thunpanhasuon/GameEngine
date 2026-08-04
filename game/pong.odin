package game
import "core:math"
import "core:math/rand"
import audio "../audio"
import object "../object"

FIELD_WIDTH  :: 800.0
FIELD_HEIGHT :: 600.0

/* paths are relative to the working dir, so run the exe from the repo root.
   square waves cut through the mix for hits, sine is softer for the walls */
SFX_PADDLE :: "sounds/cursor_1_square.wav"
SFX_WALL   :: "sounds/cursor_2_sine.wav"
SFX_SCORE  :: "sounds/error_1_saw.wav"

collision :: proc(box_a: object.Box, box_b: object.Box) -> bool {
  return box_a.x < box_b.x + box_b.w &&
         box_a.x + box_a.w > box_b.x &&
         box_a.y < box_b.y + box_b.h &&
         box_a.y + box_a.h > box_b.y
}

update_ball :: proc(o: ^object.GameObject, a: ^object.GameObject, b: ^object.GameObject, dt: f32) {
    o.box.x += o.velocity.velx * dt
    o.box.y += o.velocity.vely * dt

    /* check player ? or Ai ? only flip when the ball is heading into the
       paddle, otherwise it keeps flipping while overlapping and the sfx
       machine-guns */
    hit_a := collision(o.box, a.box) && o.velocity.velx < 0
    hit_b := collision(o.box, b.box) && o.velocity.velx > 0
    if hit_a || hit_b {
        audio.play_sfx(SFX_PADDLE)
        o.velocity.velx *= -1
    }

    /* check wall: top and bottom, clamp back inside so the flip can't
       retrigger next frame */
    if o.box.y < 0 {
        o.box.y = 0
        audio.play_sfx(SFX_WALL)
        o.velocity.vely *= -1
    }
    if o.box.y + o.box.h > 600 {
        o.box.y = 600 - o.box.h
        audio.play_sfx(SFX_WALL)
        o.velocity.vely *= -1
    }

    /* reset: serve back toward whoever conceded, with a random vertical lean */
    if o.box.x + o.box.w >= 800 || o.box.x < 0 {
        options := []int {-1, 1}
        audio.play_sfx(SFX_SCORE)
        o.box.x = 800.0 / 2.0
        o.box.y = 600.0 / 2.0
        o.velocity.velx *= -1
        o.velocity.vely = abs(o.velocity.vely) * f32(rand.choice(options))
    }
}
/* ai tuning knobs — this is the whole difficulty dial:
   REACT_DIST: how close the ball has to be before the ai starts tracking it.
               a paddle that tracks from across the field never loses.
   AIM_BIAS:   fraction of the paddle's half-height it deliberately misaims by,
               so the ball comes off the edge and rallies stay interesting.
   DEADZONE:   px of slop before it bothers moving, keeps it from vibrating. */
AI_REACT_DIST :: 480.0
AI_AIM_BIAS   :: 0.35
AI_DEADZONE   :: 4.0

/* where the ball will cross target_x, accounting for the bounces it takes on
   the way there. free-flight y is folded back into the field: the path mirrors
   every (field height - ball height), so a triangle wave gives the real y */
predict_ball_y :: proc(b: ^object.GameObject, target_x: f32) -> f32 {
    span := FIELD_HEIGHT - b.box.h
    if b.velocity.velx == 0.0 || span <= 0.0 {
        return b.box.y
    }

    t := (target_x - b.box.x) / b.velocity.velx
    if t <= 0.0 {
        return b.box.y
    }

    y := math.mod(b.box.y + b.velocity.vely * t, span * 2.0)
    if y < 0.0 {
        y += span * 2.0
    }
    if y > span {
        y = span * 2.0 - y
    }
    return y
}

update_ai :: proc(o: ^object.GameObject, b: ^object.GameObject, dt: f32) {
    /* the ai sits on whichever side of the field it spawned on, so "incoming"
       is the ball travelling toward that side */
    on_right := o.box.x > b.box.x
    incoming := b.velocity.velx > 0.0 if on_right else b.velocity.velx < 0.0
    /* the face the ball actually makes contact with */
    face := o.box.x - b.box.w if on_right else o.box.x + o.box.w

    /* park at the centre unless there's a ball worth chasing: idle in the
       middle covers both corners equally, which is what a good player does */
    target := (FIELD_HEIGHT - o.box.h) / 2.0

    if incoming && abs(face - b.box.x) < AI_REACT_DIST {
        hit_y := predict_ball_y(b, face) + b.box.h / 2.0
        /* aim off-centre in the direction the ball is already travelling: the
           return comes off the paddle edge instead of dead centre every time */
        bias := (o.box.h / 2.0) * AI_AIM_BIAS
        if b.velocity.vely < 0.0 {
            hit_y += bias
        } else if b.velocity.vely > 0.0 {
            hit_y -= bias
        }
        target = hit_y - o.box.h / 2.0
    }

    /* move toward the target at the paddle's own speed, snapping the last
       sub-step so it can't oscillate around it */
    step := o.velocity.vely * dt
    diff := target - o.box.y
    if abs(diff) > AI_DEADZONE {
        if abs(diff) <= step {
            o.box.y = target
        } else {
            o.box.y += step if diff > 0.0 else -step
        }
    }

    /* clamp after moving, otherwise the paddle can finish the frame off-screen */
    if o.box.y < 0.0 {
        o.box.y = 0.0
    }
    if o.box.y + o.box.h > FIELD_HEIGHT {
        o.box.y = FIELD_HEIGHT - o.box.h
    }
}
update_player :: proc(o: ^object.GameObject, lx: f32, dt: f32) {

    o.box.y += lx * o.velocity.vely * dt

    if o.box.y < 0.0 {
        o.box.y = 0.0
    }

    if o.box.y + o.box.h > 800.0 {
        o.box.y = 800.0 - o.box.h
    }

}