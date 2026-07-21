#!/usr/bin/env python3
"""Audit the SwiftUI sources for the two accessibility regressions that ship silently.

Neither failure is visible in review: the screen looks finished, and the app
builds and runs. They only surface for a reader using VoiceOver or a larger text
size — which, for a job-search app, is a reader with more at stake than most.

  1. An icon-only control with no accessibility label. VoiceOver falls back to
     the raw SF Symbol, so a destructive overflow menu announces itself as
     "ellipsis circle", or as nothing at all.

  2. Text pinned to a fixed point size. `Font.system(size:)` does not respond to
     Dynamic Type, unlike the text styles (`.body`, `.title`…), so a 9pt label
     stays 9pt at every accessibility setting. Use the `scaledFont(_:)` /
     `displayFont(_:)` modifiers in `Support/Theme.swift` instead.

This runs on the host rather than as an XCTest because the iOS Simulator
sandboxes the test bundle out of the checkout — `contentsOfDirectory` on the
source tree fails with EPERM, so a test can read the rule but never the sources.

Run from the repository root:

    python3 Tools/AuditAccessibility.py
    python3 Tools/AuditAccessibility.py --self-test

Exits non-zero when a control is unnamed or copy is pinned, so it can gate a
release the same way `AuditLocalization.py` does.
"""
import pathlib
import re
import sys

VIEW_DIRECTORIES = ["ResumeStudio/Views", "ResumeStudio/Support"]

# The two template preview cards draw a *miniature of a printed page* — the type
# inside them is artwork representing a résumé, not interface copy, and it has to
# stay proportional to the thumbnail. Everything else scales.
FIXED_TYPE_ALLOWED = {
    "TemplatePreviewCard.swift",
    "CoverLetterTemplateCard.swift",
}

# Shapes an icon-only control takes in this codebase.
CONTROL_OPENERS = ["label: {", "NavigationLink(value: "]


def matching_brace(text, start):
    """Index of the `}` closing the `{` at `start`, or None."""
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return None


def line_number(text, index):
    return text.count("\n", 0, index) + 1


def unlabelled_icon_controls(source, filename):
    """Controls whose label is an icon carrying no name.

    Deliberately narrow: it reports only what it is sure of, because an audit
    that fails spuriously gets switched off rather than fixed. It will miss some
    unnamed controls; it must never invent one.
    """
    findings = []
    for opener in CONTROL_OPENERS:
        position = 0
        while True:
            found = source.find(opener, position)
            if found < 0:
                break
            position = found + len(opener)

            open_brace = source.find("{", found)
            if open_brace < 0:
                continue
            close_brace = matching_brace(source, open_brace)
            if close_brace is None:
                continue

            body = source[open_brace : close_brace + 1]
            # A whole screen pushed by a NavigationLink is not a label.
            if body.count("\n") > 8:
                continue
            if "Image(" not in body:
                continue
            # Any text in the label gives VoiceOver something real to announce.
            if "Text(" in body or "Label(" in body:
                continue
            # Named on the image, or on the control's own modifier chain.
            trailing = source[close_brace : close_brace + 400]
            if "accessibilityLabel" in body or "accessibilityLabel" in trailing:
                continue
            # A purely decorative glyph correctly hides instead of naming itself.
            if "accessibilityHidden" in body:
                continue

            symbol = re.search(r'Image\(systemName:\s*"([^"]+)"', body)
            findings.append(
                (line_number(source, found), symbol.group(1) if symbol else "icon")
            )
    return findings


TEXT_WITH_FIXED_FONT = re.compile(
    r"""Text\(                    # a Text …
        (?:[^()]|\([^()]*\))*     # … its argument, allowing one nesting level
        \)\s*
        (?:\.[A-Za-z]+\([^()]*\)\s*)*?   # … any modifiers before the font
        \.font\(\s*\.system\(size:""",
    re.VERBOSE | re.DOTALL,
)


def fixed_size_text(source, filename):
    """Interface copy pinned to a point size, which Dynamic Type cannot move.

    Only flags a fixed size that is demonstrably applied to a `Text`. Icons are
    left alone: an SF Symbol inside a fixed-size badge has to stay proportional
    to the badge, and scaling the glyph alone just overflows it.

    A site that genuinely has to stay fixed — glyph-like text drawn inside a
    fixed frame, such as initials in an avatar — opts out with a trailing
    `a11y-fixed-size:` comment carrying the reason. The marker is deliberately
    per-site and has to be written out, so the exception is a decision on the
    record rather than a name quietly added to a list in this file.
    """
    if filename in FIXED_TYPE_ALLOWED:
        return []

    lines = source.split("\n")
    findings = []
    for match in TEXT_WITH_FIXED_FONT.finditer(source):
        line = line_number(source, match.start())
        # The marker may sit on the `.font(…)` line, on the `Text(…)` that opens
        # the expression, or in a comment immediately above it — the usual place
        # once the reason runs to more than a few words.
        span = lines[max(0, line - 4) : line_number(source, match.end())]
        if any("a11y-fixed-size:" in text for text in span):
            continue
        findings.append((line, match.group(0).split("\n")[0].strip()[:60]))
    return findings


def audit(root):
    unnamed, pinned = [], []
    for directory in VIEW_DIRECTORIES:
        path = root / directory
        if not path.is_dir():
            continue
        for swift in sorted(path.glob("*.swift")):
            source = swift.read_text(encoding="utf-8")
            name = swift.name
            for line, symbol in unlabelled_icon_controls(source, name):
                unnamed.append(f"  {directory}/{name}:{line} — {symbol}")
            for line, snippet in fixed_size_text(source, name):
                pinned.append(f"  {directory}/{name}:{line} — {snippet}")
    return unnamed, pinned


SELF_TEST_CASES = [
    # (description, source, expected unnamed count, expected pinned count)
    (
        "icon-only menu with no label is reported",
        '} label: {\n  Image(systemName: "ellipsis.circle")\n}',
        1,
        0,
    ),
    (
        "label on the image satisfies the rule",
        '} label: {\n  Image(systemName: "ellipsis.circle")\n'
        '    .accessibilityLabel("Review room actions")\n}',
        0,
        0,
    ),
    (
        "label on the control's modifier chain satisfies the rule",
        '} label: {\n  Image(systemName: "plus")\n}\n'
        '.accessibilityLabel("Capture a job")',
        0,
        0,
    ),
    (
        "a label carrying text is already announceable",
        '} label: {\n  Label("Compare versions", systemImage: "arrow.left.arrow.right")\n}',
        0,
        0,
    ),
    (
        "a glyph that hides itself is not a missing label",
        '} label: {\n  Image(systemName: "sparkle").accessibilityHidden(true)\n}',
        0,
        0,
    ),
    (
        "fixed-size Text is reported",
        'Text("SHOW IN CV")\n  .font(.system(size: 9, weight: .bold))',
        0,
        1,
    ),
    (
        "fixed-size Text with an intervening modifier is reported",
        'Text(label).monospacedDigit().font(.system(size: 8))',
        0,
        1,
    ),
    (
        "a fixed-size icon is left alone",
        'Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))',
        0,
        0,
    ),
    (
        "scaled text passes",
        'Text("SHOW IN CV").scaledFont(9, relativeTo: .caption2, weight: .bold)',
        0,
        0,
    ),
    (
        "an explicit opt-out with a reason is respected",
        'Text(initials)  // a11y-fixed-size: initials fill a fixed avatar circle\n'
        "  .font(.system(size: 22, weight: .bold))",
        0,
        0,
    ),
    (
        "an opt-out written as a comment above the site is respected",
        "// a11y-fixed-size: initials stand in for a portrait inside a fixed\n"
        "// avatar circle, and scaling them overflows it.\n"
        "Text(initials)\n  .font(.system(size: 22, weight: .bold))",
        0,
        0,
    ),
    (
        "an unrelated comment above the site does not excuse it",
        "// The reader's initials, shown when no portrait is set.\n"
        'Text(initials)\n  .font(.system(size: 22, weight: .bold))',
        0,
        1,
    ),
]


def self_test():
    failures = 0
    for description, source, expect_unnamed, expect_pinned in SELF_TEST_CASES:
        unnamed = len(unlabelled_icon_controls(source, "Sample.swift"))
        pinned = len(fixed_size_text(source, "Sample.swift"))
        if unnamed != expect_unnamed or pinned != expect_pinned:
            failures += 1
            print(
                f"FAIL {description}\n"
                f"     unnamed {unnamed} (expected {expect_unnamed}), "
                f"pinned {pinned} (expected {expect_pinned})"
            )
        else:
            print(f"ok   {description}")
    if failures:
        print(f"\n{failures} rule test(s) failed.")
        return 1
    print(f"\nAll {len(SELF_TEST_CASES)} rule tests passed.")
    return 0


def main():
    if "--self-test" in sys.argv:
        return self_test()

    root = pathlib.Path(__file__).resolve().parent.parent
    unnamed, pinned = audit(root)

    if unnamed:
        print(
            f"{len(unnamed)} icon-only control(s) ship without an accessibility label.\n"
            'Add `.accessibilityLabel("…")` naming the action, not the glyph\n'
            '("Review room actions", not "Ellipsis"):\n'
        )
        print("\n".join(unnamed) + "\n")

    if pinned:
        print(
            f"{len(pinned)} piece(s) of copy are pinned to a point size and cannot\n"
            "respond to Dynamic Type. Use `scaledFont(_:relativeTo:)` or\n"
            "`displayFont(_:)` from Support/Theme.swift:\n"
        )
        print("\n".join(pinned) + "\n")

    if unnamed or pinned:
        return 1

    print("Accessibility audit passed: every icon-only control is named, and no copy is pinned.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
