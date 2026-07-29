"""Export reference traces from the Python `buraco` engine for Dart parity tests.

Run against the research repo this game was forked from:

    uv run --project ../canastra-thesis python tool/export_parity_traces.py \
        --out test/data/parity_traces.json

For each trace we record the post-shuffle deck order, then every step's full
sorted legal-action id set and the action actually taken, then the final
itemised round scores. `test/parity_test.dart` deals from the same deck order,
replays the same actions, and asserts the Dart engine offers exactly the same
legal moves at every step and lands on the same scores — which is what makes
the port trustworthy rather than merely plausible.
"""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

from buraco.engine.actions import decode, encode
from buraco.engine.legal import legal_actions
from buraco.engine.scoring import round_scores
from buraco.engine.state import deal_round
from buraco.engine.turns import apply_action
from buraco.profiles import load_profile


class RecordingRandom(random.Random):
    """A Random that remembers the deck order it produced."""

    recorded: list[int] | None = None

    def shuffle(self, x, *args, **kwargs):  # type: ignore[override]
        super().shuffle(x, *args, **kwargs)
        self.recorded = list(x)


def run_trace(profile: str, num_players: int, seed: int) -> dict:
    cfg = load_profile(profile, num_players=num_players)
    slots = cfg.meld.max_meld_slots
    rng = RecordingRandom(seed)
    state = deal_round(cfg, rng, first_player=0)
    stock = rng.recorded
    assert stock is not None

    picker = random.Random(seed ^ 0x5EED)
    steps = []
    while not state.round_over and len(steps) < 4000:
        legal = sorted(encode(a, slots) for a in legal_actions(state))
        assert legal, "the legal-action set must never be empty"
        # Bias away from ending the round instantly so traces stay interesting.
        pool = [a for a in legal if a != legal[-1]] or legal
        chosen = picker.choice(pool if picker.random() < 0.85 else legal)
        steps.append({"legal": legal, "action": chosen})
        apply_action(state, decode(chosen, slots))

    return {
        "profile": profile,
        "num_players": num_players,
        "seed": seed,
        "stock": stock,
        "steps": steps,
        "round_over": state.round_over,
        "went_out_side": state.went_out_side,
        "end_reason": None if state.end_reason is None else int(state.end_reason),
        "scores": round_scores(state),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--per-profile", type=int, default=6)
    args = parser.parse_args()

    setups = [
        ("buraco", 2), ("buraco", 4),
        ("canasta", 2), ("canasta", 4),
        ("biriba", 2), ("biriba", 4),
        ("rummy", 2),
    ]
    traces = [
        run_trace(profile, players, seed)
        for profile, players in setups
        for seed in range(args.per_profile)
    ]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({"traces": traces}))
    steps = sum(len(t["steps"]) for t in traces)
    print(f"wrote {len(traces)} traces, {steps} steps -> {args.out}")


if __name__ == "__main__":
    main()
