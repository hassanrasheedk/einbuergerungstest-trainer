# Design

Mode: Operate (native iOS). HIG structure; the brand lives in tint, type rhythm and motion.

## World

Königsblau school ink: the blue fountain-pen ink every German pupil writes their first Diktat in. One ink tint on system grouped backgrounds, like ink on an exercise book, nothing else decorative.

- Tint: Königsblau `#2348C9` (light) / `#4F72F0` (dark). Interactive only.
- Correct: system green. Wrong: system red. Shaky/review: system orange. New: tertiary fill.
- Type: SF Pro via system text styles. Question text `.title3.weight(.semibold)`; answers `.body`; meta `.footnote` secondary with monospaced digits for numbers.
- Icons: SF Symbols only.

## Components

- Answer row: full-width rounded rect (14 pt continuous), secondary grouped background, leading status glyph. Press scales to 0.97 (120 ms ease-out). Revealed state fills green/red at 14 % with a 1 pt stroke; other options fade to 45 %.
- Primary action: `.borderedProminent`, large control size, pinned to the bottom safe area.
- Mastery bar: one capsule across all 310 questions, segmented sicher / gelernt / wackelig / neu.

## Motion

- Answer reveal: 180 ms ease-out color fill + haptic (success/error). The one authored moment.
- Exam result: number counts up once (rare, so allowed to delight). Reduce Motion: no count-up.
- Everything else: system transitions only.
