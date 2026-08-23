---
tags: [feature, pro, handengine]
---

# Hand Mouse

Front camera → Vision hand pose → cursor and gestures. All on device.

## The pose latch (the core idea)

Poses are **scored** continuously (0–1) from weighted finger-extension amounts,
not decided by a tree of yes/no flags. A pose, once committed, is **latched**:
a challenger must clear three gates to take over —

1. **dwell** — no change considered right after a commit
2. **evidence** — the challenger leads continuously for a span of *time*
3. **margin** — and leads by a clear score gap, not a tie

A drifting or half-relaxed hand fails the margin gate and stays put.

## Per-gesture policy

The lock protects *continuous* actions and stays out of the way of discrete ones.

| Pose | Stickiness | Why |
|---|---|---|
| Pointer | 1.35× | steering runs for seconds while the hand drifts |
| Fist (dragging) | 2.2× | dropping a window mid-drag is the worst failure |
| Palm / Scroll | 1.0× | continuous, but a wrong read is cheap |
| Thumbs-up / Shaka | 0.65×, then released after firing | one-shots; don't strand the user |
| Pinch (click) | never latched | it's a modifier on the held pose, not a pose |

## Calibration

Two seconds with an open hand takes the **median** of each finger's extension
ratio and scales every threshold to that hand. This is the single biggest fix
for "poses feel touchy" — the defaults are an average hand, and hands vary.

## Tuning

Steady / Balanced / Quick presets write two sliders (Lock strength, Switch
delay); the sliders are then the source of truth so fine-tuning sticks.

**Do not regress:** a pose change must NOT reset the cursor filter — the knuckle
anchor is identical across poses, and resetting it is what made the cursor jump.

Related: [[Gesture Studio]], [[Decisions#Time not frames]]
