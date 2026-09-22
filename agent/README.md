# Agent harness — let an external "brain" play the platformer

This folder exposes a **step-based control interface** so an external program
(e.g. the JEV decisions model) can play Forest Kingdom Platformer. The game
itself is **not modified** (no gameplay change): input is injected by toggling
the same `InputMap` actions a human would use.

## Why step-based?

A real-time platformer needs frame-accurate input. A model call (JEV ~0.8 s)
is far too slow to sit in that loop. So:

* The world is **paused between decisions** — nothing moves until the brain
  asks for a step, so model latency is irrelevant.
* A **step** advances exactly N physics frames with a chosen input state.
* A brain picks a **macro-action** (or a target platform); a driver expands it
  into fixed-frame sub-steps. No model call inside a jump.

## Files

| File | Role |
|---|---|
| `agent_runner.gd` + `.tscn` | Godot side: loads a level, freezes it, speaks the JSON protocol on stdin/stdout, injects input, steps the sim. |
| `driver.py` | Python side: spawns the harness, drives the loop, houses the brains. |

## Protocol (one JSON per line; harness lines prefixed `@@`)

Harness → brain:

```json
@@{"type":"hello","level":"...","name":"...","fps":60,"controls":[...],
   "platforms":[{"x":..,"y":..,"w":..,"h":..}],"goal":{"x":..,"y":..},
   "spawn":{"x":..,"y":..},"killzone_top_y":..}
@@{"type":"state","tick":N,"pframes":M,"time":..,"lives":3,"coins":0,
   "player":{"x":..,"y":..,"vx":..,"vy":..,"on_floor":true,"climbing":false},
   "goal":{...},"enemies":[...],"hazards":[...],"won":false,"game_over":false,
   "killzone_top_y":..}
@@{"type":"bye"}
```

brain → harness:

```json
{"cmd":"step","frames":12,"input":{"left":false,"right":true,"jump":false,"up":false,"down":false}}
{"cmd":"state"}
{"cmd":"quit"}
```

## Running

```bash
# one level, scripted reference brain
python3 agent/driver.py --brain scripted_nav --level res://scenes/levels/level_1_1.tscn

# JEV navigator (needs OPENROUTER_API_KEY in env or ~/.openclaw/.env)
python3 agent/driver.py --brain jev_nav --level res://scenes/levels/level_1_1.tscn

python3 agent/driver.py --list-macros
```

Requires the `godot` binary (4.7.x) on PATH. Everything runs **headless**
(no window), so it is fast and scriptable.

## Brains

* `scripted`     — heuristic over macro-actions (reference).
* `jev`          — JEV picks a macro-action every turn (direct low-level control).
* `scripted_nav` — a scripted **navigator** picks the next platform; a calibrated
                   **reflex executor** performs the jump.
* `jev_nav`      — **JEV picks the next platform to head to**; the reflex executor
                   does the frame-accurate jump. ← the interesting one.

## Measured physics (used by the reflex executor)

From a per-frame trace of the real game (flat ground, full speed 220 px/s):

* Jump launch `v0 = 530 px/s`, rise gravity `980`, fall gravity `1764` (1.8×).
* Max jump **height ≈ 143 px**, max horizontal **range ≈ 208 px**.
* `hop_right` ≈ 185 px, `hop_far_right` ≈ 208 px (macro-actions).

The executor computes the take-off x from a closed-form ballistic solution and
lands on the target platform; platforms are split into segments around hazards
so a "gap" is never jumped blindly into spikes.

## Results (level 1-1 苏醒之林)

| brain | outcome | notes |
|---|---|---|
| `scripted` (macro heuristic) | dies at the spike field | fires a hop one step too late |
| `jev` (direct macro control) | GAME_OVER at x≈676 | the model hops constantly, never uses `run_right` to position; a decisions model can't do frame-level timing |
| `scripted_nav` | **WON**, 0 lives lost, sim 10.0 s | reference route: ground → P5 → far ground → goal |
| `jev_nav` | **WON**, 0 lives lost, sim 10.0 s, 183 turns | JEV chooses the same correct platform sequence; cost ≈ $0.0003/run |

Takeaway: JEV clears the level when it is used for what it is good at —
**decisions** (which platform next) — with a reflex layer for frame-accurate
motor control. Raw low-level control from the decisions model fails.

Other levels (1-2/1-3/1-4) are **not yet** cleared by the executor: they need
ladder support (1-3) and moving-platform support (1-4); 1-2 needs hazard/
platform tuning. See `PLAN` notes in the project memory.

## Recording a run to video

`replay_runner.gd/.tscn` replays a recorded per-frame input list **unstoppable**
so the level can be rendered. `driver.py --trace <file>` saves the actions;
`make_replay.py` flattens them to one input dict per physics frame; then Godot's
Movie Maker (under Xvfb) renders it to AVI:

```bash
python3 agent/driver.py --brain jev_nav --trace /tmp/run.json --quiet
python3 agent/make_replay.py /tmp/run.json /tmp/frames.json
xvfb-run -a -s "-screen 0 1280x720x24" \
  env PF_REPLAY=/tmp/frames.json PF_LEVEL=res://scenes/levels/level_1_1.tscn \
  godot --path . --write-movie /tmp/out.avi --fixed-fps 60 res://agent/replay_runner.tscn
ffmpeg -y -i /tmp/out.avi -c:v libx264 -pix_fmt yuv420p -crf 23 /tmp/out.mp4
```

The runner quits ~1.3 s after the goal (before the level auto-advances), so the
win banner is captured and the recording stops cleanly. Sample output:
`media/jev-wins-level_1_1.mp4`.

## Harness implementation notes / gotchas

* The runner node is `PROCESS_MODE_ALWAYS`, but the **level is explicitly set
  to `PROCESS_MODE_PAUSABLE`** — otherwise the level inherits ALWAYS and keeps
  simulating in real time while "paused" (this bug silently broke determinism).
* The runner runs *before* the player within a physics frame (verified), so the
  frame counter pauses one frame late to yield exactly N player frames.
* `hold_to_auto_jump` is turned **off** in agent mode: auto-rejump makes the
  executor's landings fire an unintended second jump.
* Input is injected with `Input.action_press/release` (synthetic key events were
  unreliable under pause — a held key read as released after one frame).
