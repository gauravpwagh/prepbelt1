"""Python port of prep_core's belt policy, planner and catch-up, used to check
the design maths (Goal 5) where no Dart SDK is available.

Keep in step with packages/prep_core/lib/src/{belt_policy,effective_due,
planner,catch_up}.dart. Dates are plain day numbers.

Run: python3 tool/sim/planner_check.py
"""
import math
import random
import sys

LADDER = {0: None, 1: 1, 2: 3, 3: 7, 4: 16, 5: 35}  # step -> interval
SHAKY = {1: 1, 2: 2, 3: 4, 4: 8, 5: 18}
RESERVE_FRACTION, REVIEW_FRACTION, MIN_REVIEW = 0.30, 0.25, 3
HORIZON, RISK_DAYS = 14, 7


class Item:
    def __init__(self, nid, base, subject, sort):
        self.id, self.base, self.subject, self.sort = nid, base, subject, sort
        self.belt, self.ladder_due, self.last = 0, None, None
        self.resched = False
        self.first_study_day = None


def review_cost(base):
    return max(MIN_REVIEW, math.ceil(base * REVIEW_FRACTION))


def deadline_for(item, exams, today):
    ds = [d for subj, d in exams if item.subject in subj and d > today]
    return min(ds) if ds else None


def effective_due(item, deadline):
    if item.ladder_due is None:
        return None
    if deadline is None:
        return item.ladder_due
    cap = deadline - 1
    if item.last is not None and cap <= item.last:
        return item.ladder_due
    return min(item.ladder_due, cap)


def build_plan(items, exams, today, budget):
    unread = sorted([i for i in items if i.belt == 0], key=lambda i: i.sort)
    due = []
    for i in items:
        if i.belt == 0:
            continue
        dl = deadline_for(i, exams, today)
        eff = effective_due(i, dl)
        if eff <= today:
            due.append((i, dl, eff))

    def key(t):
        i, dl, eff = t
        return (dl - today if dl is not None else 1 << 30, -(today - eff), i.belt, i.sort)

    due.sort(key=key)
    reserve = 0
    if unread:
        reserve = min(budget, max(math.ceil(budget * RESERVE_FRACTION), unread[0].base))
    review_share = budget - reserve
    left = review_share
    placed = set()
    for i, dl, eff in due:
        c = review_cost(i.base)
        if c <= left:
            placed.add(i.id)
            left -= c
    first_left = reserve + left
    firsts = []
    for u in unread:
        if u.base <= first_left:
            firsts.append(u)
            first_left -= u.base
    for i, dl, eff in due:
        if i.id in placed:
            continue
        c = review_cost(i.base)
        if c <= first_left:
            placed.add(i.id)
            first_left -= c
    reviews = [t for t in due if t[0].id in placed]
    waiting = [t for t in due if t[0].id not in placed]
    used = sum(review_cost(t[0].base) for t in reviews) + sum(u.base for u in firsts)
    assert used <= budget, (used, budget)
    if unread and unread[0].base <= budget:
        assert firsts, "reserve must fit at least one first reading"
    return dict(reviews=reviews, firsts=firsts, waiting=waiting,
                review_share=review_share,
                waiting_minutes=sum(review_cost(t[0].base) for t in waiting))


def propose(items, exams, today, plan):
    waiting_ids = {t[0].id for t in plan["waiting"]}
    cap = [plan["review_share"]] * HORIZON
    cap[0] = 0
    for i in items:
        if i.belt == 0 or i.id in waiting_ids:
            continue
        eff = effective_due(i, deadline_for(i, exams, today))
        d = eff - today
        if 1 <= d < HORIZON:
            cap[d] -= review_cost(i.base)
    moves, wont = [], 0
    for i, dl, eff in plan["waiting"]:
        c = review_cost(i.base)
        latest = HORIZON - 1 if dl is None else dl - today - 1
        if dl is not None and latest <= 0:
            wont += 1
            continue
        last = min(latest, HORIZON - 1)
        chosen = next((d for d in range(1, last + 1) if cap[d] >= c), None)
        if chosen is None:
            if dl is not None and latest <= HORIZON - 1:
                chosen = latest
                wont += 1
            else:
                continue
        cap[chosen] -= c
        moves.append((i, today + chosen))
    return moves, wont


def grade(item, g, today):
    b = item.belt
    if g == "solid":
        nb = min(5, b + 1)
        n = LADDER[nb]
    elif g == "shaky":
        nb, n = b, SHAKY[b]
    else:
        nb, n = max(1, b - 1), 1
    item.belt, item.ladder_due, item.last, item.resched = nb, today + n, today, False


def simulate(seed, n_items=300, budget=90, days=90, miss=0.15):
    rnd = random.Random(seed)
    items = [Item(k, rnd.choice([20, 30, 30, 30, 40, 50]), k % 6, k) for k in range(n_items)]
    exams = [({0, 1, 2}, 45), ({3, 4, 5}, 80), ({1}, 80)]  # subject 1 shared
    worst_ratio, worst_exam_week, reviewed_before = 0.0, 0.0, {}
    open_days = []
    for today in range(days):
        if rnd.random() < miss:
            continue
        open_days.append(today)
        plan = build_plan(items, exams, today, budget)
        if plan["waiting"]:
            moves, _ = propose(items, exams, today, plan)
            for i, d in moves:
                i.ladder_due, i.resched = d, True
            plan = build_plan(items, exams, today, budget)
        if plan["review_share"] > 0:
            ratio = plan["waiting_minutes"] / plan["review_share"]
            exam_week = any(0 < d - today <= RISK_DAYS for _, d in exams)
            if exam_week:
                worst_exam_week = max(worst_exam_week, ratio)
            else:
                worst_ratio = max(worst_ratio, ratio)
        for i, dl, eff in plan["reviews"]:
            reviewed_before.setdefault(i.id, []).append(today)
            r = rnd.random()
            grade(i, "solid" if r < 0.6 else "shaky" if r < 0.9 else "forgot", today)
        for u in plan["firsts"]:
            u.belt, u.ladder_due, u.last, u.first_study_day = 1, today + 1, today, today
    # Goal 5 second half: items first studied >= 3 days before a deadline that
    # falls inside the run get a planned review before that exam.
    misses = 0
    for i in items:
        if i.first_study_day is None:
            continue
        for subj, d in exams:
            if i.subject in subj and d <= days and d - i.first_study_day >= 3:
                if not any(i.first_study_day < o < d for o in open_days):
                    continue  # app never opened in between: no review was possible
                if not any(i.first_study_day < r < d for r in reviewed_before.get(i.id, [])):
                    misses += 1
    studied = sum(1 for i in items if i.first_study_day is not None)
    return worst_ratio, worst_exam_week, misses, studied


def unit_checks():
    # Reserve with defaults: 90 budget, 30-min item -> reserve 30 (fits).
    it = [Item(0, 30, 0, 0)]
    p = build_plan(it, [], 0, 90)
    assert p["firsts"] and p["review_share"] == 60, p
    # Small budget: 30/30 -> reserve 30, review share 0.
    p = build_plan([Item(0, 30, 0, 0)], [], 0, 30)
    assert p["firsts"] and p["review_share"] == 0, p
    # Exam cap cases, last review T=10, ladder due T+7.
    x = Item(0, 30, 0, 0); x.belt, x.last, x.ladder_due = 2, 10, 17
    assert effective_due(x, None) == 17
    assert effective_due(x, 50) == 17
    assert effective_due(x, 13) == 12
    assert effective_due(x, 12) == 11
    assert effective_due(x, 11) == 17  # exam tomorrow: no cap
    print("unit checks: OK")


if __name__ == "__main__":
    unit_checks()
    # Goal 5 (D12): outside the 7 days before an exam, waiting minutes stay
    # within 3 days of review share. Inside exam week the shortfall is real and
    # is reported to the user instead (wontFit + extra minutes per day).
    worst, worst_week, fails = 0.0, 0.0, 0
    for seed in range(1, 21):
        ratio, week, misses, studied = simulate(seed)
        worst, worst_week = max(worst, ratio), max(worst_week, week)
        fails += misses
        print(f"seed {seed:2d}: studied {studied:3d}  waiting/share {ratio:4.2f}  exam-week {week:5.2f}  missed-before-exam {misses}")
    print(f"WORST outside exam week {worst:.2f} (limit 3.00); exam week {worst_week:.2f} (reported, not bounded); "
          f"items missing a pre-exam review: {fails}")
    sys.exit(0 if worst <= 3.0 and fails == 0 else 1)
