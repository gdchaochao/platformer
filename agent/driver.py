#!/usr/bin/env python3
"""Forest Kingdom Platformer — agent driver.

Drives the Godot agent harness (agent/agent_runner.tscn) over a line-based
JSON protocol on stdin/stdout. A pluggable "brain" picks the action(s) each
decision.

Brains
  scripted     : hand-written heuristic over macro-actions (reference)
  jev          : JEV decisions model picks a macro-action every turn
  scripted_nav : scripted NAVIGATOR - picks the next platform, reflex
                 executor performs the jump
  jev_nav      : JEV picks the next platform to head to; a reflex executor
                 performs the frame-accurate jump

Why two levels?
  JEV is a *decisions* (classification/judgment) model: it is good at
  "which option" but cannot do frame-accurate motor timing. So the navigator
  brains split the job: the model decides *where to go*, a calibrated reflex
  layer (real physics, measured jump arcs) decides *exactly how to jump*.

Usage
  python3 agent/driver.py --brain scripted --level res://scenes/levels/level_1_1.tscn
  python3 agent/driver.py --brain jev_nav --level res://scenes/levels/level_1_1.tscn
  python3 agent/driver.py --list-macros

Env
  OPENROUTER_API_KEY  (or read from ~/.openclaw/.env)
"""

from __future__ import annotations

import argparse
import json
import math
import os
import queue
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)

JEV_API = "https://openrouter.ai/api/alpha/decisions"
JEV_MODEL = os.environ.get("JEV_MODEL", "~typesafe/jev-latest")

# ---- measured physics (from tools: per-frame trace of the real game) -------
V0 = 530.0        # jump launch speed (px/s)
G_UP = 980.0      # gravity while rising with jump held
G_DOWN = 1764.0   # gravity while falling (gravity_scale_release = 1.8)
VX = 220.0        # max horizontal speed
BODY_HW = 8.0     # player half width
PX_PER_FRAME = VX / 60.0


# ---------------------------------------------------------------------------
# Macro-actions: name -> list of (input_dict, frames)   (60 physics frames/s)
# ---------------------------------------------------------------------------
RUN = 12


def _run(direction, frames=RUN):
    return [({direction: True}, frames)]


def _jump(dirkey=None, hold=20, tail=40):
    up = {"jump": True}
    if dirkey:
        up[dirkey] = True
    down = {dirkey: True} if dirkey else {}
    return [(up, hold), (down, tail)]


MACROS = {
    "wait":           [({}, RUN)],
    "run_right":      _run("right"),
    "run_left":       _run("left"),
    "run_right_long": _run("right", 36),
    "run_left_long":  _run("left", 36),
    "hop_right":      _jump("right"),
    "hop_left":       _jump("left"),
    "hop_up":         _jump(None),
    "hop_far_right":  _jump("right", 32, 44),
    "hop_far_left":   _jump("left", 32, 44),
    "climb_up":       [({"up": True}, 30)],
    "climb_down":     [({"down": True}, 30)],
}


# ---------------------------------------------------------------------------
# Jump ballistics (matches the measured per-frame trace)
# ---------------------------------------------------------------------------

def jump_airtime(h_up):
    """Return (t_rise, t_fall) for a full-hold jump landing h_up px above
    (h_up>0) or below (h_up<0) the take-off height. None if unreachable."""
    H = V0 * V0 / (2 * G_UP)          # max height 143.3
    if h_up > H - 1:
        return None
    t1 = V0 / G_UP
    drop = (H - h_up) if h_up >= 0 else (H + (-h_up))
    t2 = math.sqrt(2 * drop / G_DOWN)
    return t1, t2


def jump_range(h_up):
    a = jump_airtime(h_up)
    return None if a is None else VX * (a[0] + a[1])


# ---------------------------------------------------------------------------
# Godot harness client
# ---------------------------------------------------------------------------

class Game:
    def __init__(self, level, godot="godot"):
        env = dict(os.environ, PF_LEVEL=level, GODOT_SILENCE_ROOT_WARNING="1")
        self.p = subprocess.Popen(
            [godot, "--headless", "--path", PROJ, "res://agent/agent_runner.tscn"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, bufsize=1, env=env)
        self.q: queue.Queue = queue.Queue()
        self.t = threading.Thread(target=self._reader, daemon=True)
        self.t.start()
        self.hello = self._recv(timeout=30)
        self.platforms = self.hello.get("platforms", [])
        self.hazards = None  # filled from first state
        self._last_pf = None

    def _reader(self):
        for line in self.p.stdout:
            if line.startswith("@@"):
                try:
                    self.q.put(json.loads(line[2:]))
                except json.JSONDecodeError:
                    pass
        self.q.put(None)

    def _recv(self, timeout=15):
        try:
            msg = self.q.get(timeout=timeout)
        except queue.Empty:
            raise RuntimeError("harness timeout waiting for message")
        if msg is None:
            raise RuntimeError("harness closed stdout")
        return msg

    def send(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n")
        self.p.stdin.flush()

    def step(self, input_dict, frames):
        self.send({"cmd": "step", "frames": int(frames), "input": input_dict})
        st = self._recv()
        st["platforms"] = self.platforms
        if self._last_pf is not None and "pframes" in st and frames > 0:
            act = st["pframes"] - self._last_pf
            if act != frames:
                print("   [warn] requested %d physics frames, advanced %d" % (frames, act))
        self._last_pf = st.get("pframes")
        return st

    def run_seq(self, seq):
        st = None
        for inp, frames in seq:
            st = self.step(inp, frames)
            if st.get("won") or st.get("game_over"):
                break
        return st

    def close(self):
        try:
            self.send({"cmd": "quit"})
            self._recv(timeout=5)
        except Exception:
            pass
        try:
            self.p.wait(timeout=5)
        except Exception:
            self.p.kill()


# ---------------------------------------------------------------------------
# World model: surfaces (platforms split around hazards) + reachability
# ---------------------------------------------------------------------------

def build_surfaces(platforms, hazards, goal):
    hz = [(h["x"] - BODY_HW - 2, h["x"] + h["w"] + BODY_HW + 2) for h in hazards]
    out = []
    for q in platforms:
        x1, x2, top = q["x"], q["x"] + q["w"], q["y"]
        segs = [(x1, x2)]
        for a, b in hz:
            ns = []
            for s, e in segs:
                if b <= s or a >= e:
                    ns.append((s, e)); continue
                if a > s:
                    ns.append((s, a))
                if b < e:
                    ns.append((b, e))
            segs = ns
        for s, e in segs:
            if e - s > 12:
                out.append({"x1": s, "x2": e, "top": top})
    if goal:
        gx = goal["x"]
        top = 320.0
        for q in platforms:
            if q["x"] <= gx <= q["x"] + q["w"]:
                top = q["y"]
        out.append({"x1": gx - 30, "x2": gx + 30, "top": top, "goal": True})
    out.sort(key=lambda s: s["x1"])
    return out


def surface_under(px, feet, surfaces):
    c = [s for s in surfaces if s["x1"] - 6 <= px <= s["x2"] + 6 and abs(feet - s["top"]) < 5]
    return min(c, key=lambda s: abs(s["top"] - feet)) if c else None


def same(a, b):
    return a is not None and b is not None and (round(a["x1"]), round(a["x2"]), round(a["top"])) == (round(b["x1"]), round(b["x2"]), round(b["top"]))


def reachable(cur, tgt):
    """Can we jump from surface `cur` to surface `tgt`?"""
    h_up = cur["top"] - tgt["top"]
    r = jump_range(h_up)
    if r is None:
        return None
    if tgt["x1"] >= cur["x2"]:
        gap = tgt["x1"] - cur["x2"]
    elif tgt["x2"] <= cur["x1"]:
        gap = cur["x1"] - tgt["x2"]
    else:
        gap = -min(cur["x2"], tgt["x2"]) + max(cur["x1"], tgt["x1"])  # overlap
    return r + 20 if gap <= r + 20 else None


# ---------------------------------------------------------------------------
# Brains
# ---------------------------------------------------------------------------

class Brain:
    name = "base"

    def decide(self, st):
        """Return a list of (input_dict, frames) to execute this turn."""
        raise NotImplementedError


class ScriptedBrain(Brain):
    name = "scripted"

    def decide(self, st):
        p = st["player"]
        a = analyze_loose(st)
        if p["climbing"]:
            return MACROS["climb_up"]
        if a["spike_in"] is not None and a["spike_in"] <= 70:
            return MACROS["hop_right"]
        if a["edge_dx"] is not None and a["edge_dx"] <= 45:
            gap = a["gap_w"] or 0
            return MACROS["hop_far_right"] if gap > 200 else MACROS["hop_right"]
        for e in st["enemies"]:
            if 0 <= e["x"] - p["x"] <= 70 and abs(e["y"] - p["y"]) < 40:
                return MACROS["hop_right"]
        return MACROS["run_right"]


def analyze_loose(st):
    p = st["player"]
    feet = p["y"] + 12.0
    cur = surface_under(p["x"], feet, build_surfaces(st["platforms"], st.get("hazards", []), st.get("goal")))
    info = {"edge_dx": None, "gap_w": None, "spike_in": None}
    if cur:
        info["edge_dx"] = cur["x2"] - p["x"]
        right = [s for s in build_surfaces(st["platforms"], st.get("hazards", []), st.get("goal")) if s["x1"] > cur["x2"] + 1]
        if right:
            info["gap_w"] = min(right, key=lambda s: s["x1"])["x1"] - cur["x2"]
    sp = [h for h in st.get("hazards", []) if h["x"] + h["w"] > p["x"] - 10]
    if sp:
        info["spike_in"] = min(sp, key=lambda q: q["x"])["x"] - p["x"]
    return info


# --- JEV direct macro control ------------------------------------------------

class JevBrain(Brain):
    name = "jev"

    ACTIONS = {
        "wait":           "stand still (~0.2s)",
        "run_right":      "run RIGHT a little (~0.2s, ~44px)",
        "run_left":       "run LEFT a little (~0.2s, ~44px)",
        "run_right_long": "run RIGHT further (~0.6s, ~130px)",
        "run_left_long":  "run LEFT further (~0.6s, ~130px)",
        "hop_right":      "jump moving RIGHT, short (~185px)",
        "hop_left":       "jump moving LEFT, short (~185px)",
        "hop_far_right":  "jump moving RIGHT, far as possible (~208px)",
        "hop_far_left":   "jump moving LEFT, far as possible (~208px)",
        "hop_up":         "jump straight up in place",
        "climb_up":       "climb UP a ladder",
        "climb_down":     "climb DOWN a ladder",
    }
    INSTRUCTIONS = (
        "You control a mushroom character in a 2D platformer. Reach the GOAL flag on the right. "
        "You have 3 lives; spikes or pits cost a life and restart you at the start. "
        "The maximum horizontal jump distance is only ~208px and you cannot jump higher than ~143px. "
        "Choose the SINGLE best action right now. Progress RIGHT toward the goal. "
        "Do not repeatedly jump when a clear path exists; run_right instead."
    )

    def __init__(self, key, verbose=True):
        self.key, self.verbose = key, verbose
        self.calls = self.cost = 0
        self.cost = 0.0
        self.history = []

    def decide(self, st):
        body = {"model": JEV_MODEL, "state": render_state(st, self.history),
                "questions": {"act": {"type": "choice", "instructions": self.INSTRUCTIONS,
                                      "criteria": dict(self.ACTIONS)}}}
        choice = jev_ask(self.key, body, verbose=self.verbose)
        self.history.append(choice)
        return MACROS.get(choice, MACROS["wait"])


# --- Navigator brains (model picks a target surface; reflex executes) -------

class NavigatorBrain(Brain):
    name = "nav"

    def __init__(self, chooser, verbose=True):
        self.chooser = chooser          # callable(st, candidates, cur) -> surface
        self.verbose = verbose
        self.target = None
        self._dir = 0
        self._air = 0
        self._rise_f = 32
        self.turns = 0
        self.replans = 0
        self._last_lives = None

    def decide(self, st):
        p = st["player"]
        self.turns += 1
        surfaces = build_surfaces(st["platforms"], st.get("hazards", []), st.get("goal"))
        feet = p["y"] + 12.0
        cur = surface_under(p["x"], feet, surfaces)

        # died / respawned -> drop the target
        if self._last_lives is not None and st["lives"] < self._last_lives:
            self.target = None
        self._last_lives = st["lives"]
        if self.target is not None and not any(same(self.target, s) for s in surfaces):
            self.target = None

        if cur is None and p["on_floor"]:
            cur = self.target if self.target else None

        # on target -> pick a new one (only when actually standing on it)
        if p["on_floor"] and same(self.target, cur):
            if self.verbose:
                print("      reached surface top=%.0f x=%.0f..%.0f" % (
                    self.target["top"], self.target["x1"], self.target["x2"]))
            self.target = None

        if self.target is None and cur is not None:
            cands = self._candidates(st, cur, surfaces)
            if cands:
                self.target = self.chooser(st, cands, cur)
                self.replans += 1
                if self.verbose and self.target:
                    print("      target -> top=%.0f x=%.0f..%.0f%s" % (
                        self.target["top"], self.target["x1"], self.target["x2"],
                        " (GOAL)" if self.target.get("goal") else ""))

        if self.target is None:
            return MACROS["run_right"]
        return self._exec(st, cur)

    def _candidates(self, st, cur, surfaces):
        p = st["player"]
        out = []
        for s in surfaces:
            if same(s, cur):
                continue
            if s["x1"] <= p["x"] - 30:      # behind us
                continue
            if reachable(cur, s):
                out.append(s)
        out.sort(key=lambda s: s["x1"])
        return out

    def _exec(self, st, cur):
        p = st["player"]
        tgt = self.target
        if p["climbing"]:
            return MACROS["climb_up"]
        if not p["on_floor"]:
            self._air += 1
            d = {"right": True} if self._dir > 0 else ({"left": True} if self._dir < 0 else {})
            if self._air <= self._rise_f:
                inp = dict(d); inp["jump"] = True
                return [(inp, 2)]
            return [(d, 2)]
        # on floor
        if cur is None:
            return MACROS["run_right"]
        h_up = cur["top"] - tgt["top"]
        rng = jump_range(h_up) or 200.0
        cx = (tgt["x1"] + tgt["x2"]) / 2.0
        takeoff = cx - rng if cx >= p["x"] else cx + rng
        lo, hi = cur["x1"] + 6, cur["x2"] - 6
        takeoff = min(max(takeoff, lo), hi)
        d = takeoff - p["x"]
        if abs(d) > 3:
            k = max(1, min(24, int(round(abs(d) / PX_PER_FRAME))))
            return [({"right": d > 0, "left": d < 0}, k)]
        self._dir = 1 if cx > p["x"] + 2 else (-1 if cx < p["x"] - 2 else 0)
        a = jump_airtime(h_up)
        self._rise_f = int(round(a[0] * 60)) if a else 32
        self._air = 0
        inp = dict({"right": True} if self._dir > 0 else ({"left": True} if self._dir < 0 else {}))
        inp["jump"] = True
        return [(inp, 2)]


def scripted_chooser(st, cands, cur):
    # furthest reachable surface toward the goal
    goal = st.get("goal")
    if goal:
        ahead = [s for s in cands if s["x1"] + s["x2"] > 2 * st["player"]["x"] - 60]
        if ahead:
            return max(ahead, key=lambda s: (s["x1"] + s["x2"]))
    return max(cands, key=lambda s: s["x1"] + s["x2"]) if cands else None


def make_jev_chooser(key, verbose=True):
    def chooser(st, cands, cur):
        p = st["player"]
        goal = st.get("goal", {})
        opts = {}
        for i, s in enumerate(cands[:5]):
            tag = "GOALFLAG" if s.get("goal") else "surface"
            opts["o%d" % i] = ("%s: x=%.0f..%.0f (center %.0f px ahead), top_y=%.0f (%s)"
                               % (tag, s["x1"], s["x2"], (s["x1"] + s["x2"]) / 2 - p["x"], s["top"],
                                  "higher" if s["top"] < cur["top"] - 2 else ("lower" if s["top"] > cur["top"] + 2 else "same height")))
            cands[i]["_id"] = "o%d" % i
        state = render_state(st)
        state += ("\nYou are standing on a surface top_y=%.0f x=%.0f..%.0f.\n"
                  "Reachable places to head to next:\n" % (cur["top"], cur["x1"], cur["x2"]))
        for k in sorted(opts):
            state += "  %s -> %s\n" % (k, opts[k])
        state += ("GOAL is at x=%.0f. Pick the option that makes the best progress toward the "
                  "GOAL without dying. You can only jump ~200px far and ~140px high." % goal.get("x", 0))
        instructions = ("You are navigating a platformer character. Each option is a place you could "
                        "jump/run to next. Choose the SINGLE best option that gets you closer to the "
                        "goal flag while staying alive (avoid falling into gaps or hitting spikes).")
        body = {"model": JEV_MODEL, "state": state,
                "questions": {"act": {"type": "choice", "instructions": instructions, "criteria": opts}}}
        choice = jev_ask(key, body, verbose=verbose)
        for s in cands:
            if s.get("_id") == choice:
                return s
        return cands[0] if cands else None
    return chooser


# ---------------------------------------------------------------------------
# JEV call
# ---------------------------------------------------------------------------

def jev_ask(key, body, verbose=True, tries=3):
    for attempt in range(tries):
        try:
            req = urllib.request.Request(
                JEV_API, data=json.dumps(body).encode(),
                headers={"Content-Type": "application/json",
                         "Authorization": "Bearer " + key})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = json.loads(r.read().decode())
            ans = data["answers"]["act"]
            if verbose:
                probs = sorted(ans.get("probabilities", {}).items(), key=lambda kv: -kv[1])[:3]
                print("   [jev] -> %-8s conf=%.2f  %s" % (ans.get("choice"), ans.get("confidence", 0), probs))
            return ans.get("choice", "")
        except (urllib.error.URLError, KeyError, json.JSONDecodeError) as e:
            print("   [jev] error (attempt %d): %s" % (attempt + 1, e))
            time.sleep(0.5)
    return ""


def render_state(st, history=()):
    p = st["player"]
    L = ["t=%.2fs lives=%d coins=%d" % (st["time"], st["lives"], st["coins"]),
         "player x=%.0f y=%.0f vx=%.0f vy=%.0f on_floor=%s climbing=%s"
         % (p["x"], p["y"], p["vx"], p["vy"], p["on_floor"], p["climbing"])]
    if st.get("goal"):
        L.append("GOAL x=%.0f (%.0f px to the right)" % (st["goal"]["x"], st["goal"]["x"] - p["x"]))
    if history:
        L.append("recent: " + " ".join(history[-6:]))
    return "\n".join(L)


# ---------------------------------------------------------------------------
# Episode / main
# ---------------------------------------------------------------------------

def load_key():
    k = os.environ.get("OPENROUTER_API_KEY", "")
    if k:
        return k
    envf = os.path.expanduser("~/.openclaw/.env")
    if os.path.exists(envf):
        for line in open(envf):
            if line.startswith("OPENROUTER_API_KEY="):
                return line.split("=", 1)[1].strip()
    return ""


def make_brain(kind, key, quiet):
    if kind == "scripted":
        return ScriptedBrain()
    if kind == "jev":
        return JevBrain(key, verbose=not quiet)
    if kind == "scripted_nav":
        return NavigatorBrain(scripted_chooser, verbose=not quiet)
    if kind == "jev_nav":
        return NavigatorBrain(make_jev_chooser(key, verbose=not quiet), verbose=not quiet)
    raise SystemExit("unknown brain")


def run_episode(args, brain):
    g = Game(args.level)
    st = g.step({}, 0)
    steps = 0
    result = "MAX_STEPS"
    trace = []
    try:
        while steps < args.max_steps:
            if st.get("won"):
                result = "WON"; break
            if st.get("game_over"):
                result = "GAME_OVER"; break
            prev = st["lives"]
            seq = brain.decide(st)
            p0 = st["player"]
            trace.append({"turn": steps, "t": st["time"], "x": p0["x"], "y": p0["y"],
                          "on_floor": p0["on_floor"], "lives": st["lives"],
                          "action": [{"keys": [k for k, v in i.items() if v], "frames": f} for i, f in seq]})
            if not args.quiet:
                print("turn %3d t=%5.2fs pos=(%.0f,%.0f) floor=%s -> %s" % (
                    steps, st["time"], p0["x"], p0["y"], p0["on_floor"],
                    " ".join("%s/%d" % (list(i.keys()) or "-", f) for i, f in seq)))
            st = g.run_seq(seq)
            if st is None:
                result = "ERR"; break
            if st["lives"] < prev:
                p = st["player"]
                print("      !! lost a life (respawn x=%.0f, lives=%d)" % (p["x"], st["lives"]))
                if isinstance(brain, NavigatorBrain):
                    brain.target = None
            steps += 1
        else:
            result = "MAX_STEPS"
    finally:
        g.close()
    if args.trace:
        with open(args.trace, "w") as f:
            json.dump({"level": args.level, "brain": brain.name, "result": result,
                       "steps": steps, "trace": trace}, f, ensure_ascii=False)
        print("trace -> %s" % args.trace)
    return result, st, steps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--brain", default="scripted_nav",
                    choices=["scripted", "jev", "scripted_nav", "jev_nav"])
    ap.add_argument("--level", default="res://scenes/levels/level_1_1.tscn")
    ap.add_argument("--max-steps", type=int, default=400)
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--trace", default="")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--list-macros", action="store_true")
    args = ap.parse_args()

    if args.list_macros:
        for n, seq in MACROS.items():
            print("%-16s %s" % (n, seq))
        return

    key = load_key()
    if "jev" in args.brain and not key:
        print("no OPENROUTER_API_KEY found", file=sys.stderr); sys.exit(2)

    t0 = time.time()
    results = []
    for r in range(args.runs):
        brain = make_brain(args.brain, key, args.quiet)
        print("=== run %d/%d  brain=%s ===" % (r + 1, args.runs, brain.name))
        res, st, steps = run_episode(args, brain)
        p = st["player"]
        print("RESULT: %-9s steps=%3d sim=%5.1fs final_x=%.0f lives=%d coins=%d"
              % (res, steps, st["time"], p["x"], st["lives"], st["coins"]))
        results.append(res)
    print("=" * 60)
    print("summary: %d runs, won=%d, wall=%.1fs" % (args.runs, results.count("WON"), time.time() - t0))


if __name__ == "__main__":
    main()
