#!/usr/bin/env python3
"""Convert a driver trace (--trace) into a flat per-frame input list for
agent/replay_runner.tscn (used to record a run to video).

    python3 agent/make_replay.py /tmp/run.json /tmp/frames.json
"""
import json
import sys


def main():
    src, dst = sys.argv[1], sys.argv[2]
    d = json.load(open(src))
    flat = []
    for turn in d["trace"]:
        for a in turn["action"]:
            inp = {k: True for k in a["keys"]}
            flat += [inp] * int(a["frames"])
    json.dump(flat, open(dst, "w"))
    print("%s -> %s : %d turns, %d frames (%.2fs @60fps), result=%s"
          % (src, dst, len(d["trace"]), len(flat), len(flat) / 60.0, d.get("result")))


if __name__ == "__main__":
    main()
