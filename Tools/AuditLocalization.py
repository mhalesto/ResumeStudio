#!/usr/bin/env python3
"""Audit the string catalogue against the source, without Xcode.

`xcodebuild` does not re-run Xcode's string extraction, so a literal added to a
view can sit outside `Localizable.xcstrings` indefinitely and silently ship
untranslated. This checks the two failure modes that caused real gaps:

  1. A localizable literal in the source that is missing from the catalogue.
  2. Display copy typed as `String`, which bypasses the catalogue entirely —
     `Text(someString)` takes the `StringProtocol` overload and never looks a
     translation up. Such properties must be `LocalizedStringResource`.

Run from the repository root:

    python3 Tools/AuditLocalization.py [language]

Exits non-zero when the catalogue is incomplete, so it can gate a release.
"""
import json
import os
import re
import sys

# String catalogues are per-target: a literal in the widget bundle is not served
# by the app's catalogue. Each target is audited against its own.
TARGETS = {
    "ResumeStudio": "ResumeStudio/Localizable.xcstrings",
    "ResumeStudioWidgets": "ResumeStudioWidgets/Localizable.xcstrings",
    "JobShareExtension": "JobShareExtension/Localizable.xcstrings",
    "ResumeStudioSafariExtension": "ResumeStudioSafariExtension/Localizable.xcstrings",
}

# SwiftUI constructs whose literal argument is looked up in the catalogue.
LOCALIZING = [
    re.compile(r'\bText\("((?:[^"\\]|\\.)+)"\)'),
    re.compile(r'\bLabel\("((?:[^"\\]|\\.)+)",\s*systemImage:'),
    re.compile(r'\bButton\("((?:[^"\\]|\\.)+)"'),
    re.compile(r'\bSection\("((?:[^"\\]|\\.)+)"\)'),
    re.compile(r'\bTextField\("((?:[^"\\]|\\.)+)"'),
    re.compile(r'\bToggle\("((?:[^"\\]|\\.)+)"'),
    re.compile(r'\bnavigationTitle\("((?:[^"\\]|\\.)+)"\)'),
    re.compile(r'\bPicker\("((?:[^"\\]|\\.)+)"'),
    re.compile(r'\bLink\("((?:[^"\\]|\\.)+)"'),
    re.compile(r'configurationDisplayName\("((?:[^"\\]|\\.)+)"'),
    re.compile(r'\.description\("((?:[^"\\]|\\.)+)"'),
    # Spoken copy localizes exactly like visible copy — the literal overloads
    # take `LocalizedStringKey`. It is easier to miss precisely because nobody
    # sees it on screen: an untranslated label is silent until a German reader
    # turns VoiceOver on and hears English.
    re.compile(r'\.accessibilityLabel\("((?:[^"\\]|\\.)+)"'),
    re.compile(r'\.accessibilityValue\("((?:[^"\\]|\\.)+)"'),
    re.compile(r'\.accessibilityHint\("((?:[^"\\]|\\.)+)"'),
]

# Property names that read as display copy rather than data or identifiers.
COPY_PROPERTY = re.compile(
    r"^\s*(?:let|var) (\w*(?:[Tt]itle|[Ll]abel|[Ss]ubtitle|[Cc]aption|[Mm]essage"
    r"|[Hh]eadline|[Pp]rompt|[Ee]yebrow|[Pp]laceholder))\s*:\s*String\b"
)


def swift_files(root):
    for dirpath, _, filenames in os.walk(root):
        for name in sorted(filenames):
            if name.endswith(".swift"):
                yield os.path.join(dirpath, name)


def audit_target(root, catalogue_path, language):
    if not os.path.isdir(root):
        return 0
    if not os.path.exists(catalogue_path):
        catalogue = {}
        print(f"  no catalogue at {catalogue_path} — any literal below cannot localize")
    else:
        catalogue = json.load(open(catalogue_path))["strings"]
    keys = set(catalogue)

    missing_keys = {}
    string_typed_copy = []
    for path in swift_files(root):
        in_view = False
        for number, line in enumerate(open(path), 1):
            if re.match(r"^(?:private )?struct \w+: View", line):
                in_view = True
            elif re.match(r"^(?:private )?(struct|enum|final class|extension)", line):
                in_view = False

            if in_view and COPY_PROPERTY.match(line):
                string_typed_copy.append(f"{path}:{number}  {line.strip()}")

            # `Text(verbatim:)` is the opt-out for brand and document chrome.
            if "verbatim:" in line:
                continue
            for pattern in LOCALIZING:
                for match in pattern.finditer(line):
                    literal = match.group(1)
                    # Interpolated and multi-line literals key differently.
                    if "\\(" in literal or "\\n" in literal:
                        continue
                    if literal not in keys:
                        missing_keys.setdefault(literal, f"{path}:{number}")

    translated = sum(
        1
        for entry in catalogue.values()
        if language in (entry.get("localizations") or {})
    )
    deliberate = sum(
        1 for entry in catalogue.values() if entry.get("shouldTranslate") is False
    )

    print(f"  catalogue: {len(catalogue)} keys")
    print(f"  {language}: {translated} translated, {deliberate} marked do-not-translate")
    print(f"  literals missing from the catalogue: {len(missing_keys)}")
    for literal, where in sorted(missing_keys.items()):
        print(f"    {literal!r}  <- {where}")

    # Informational: some of these legitimately carry user data.
    if string_typed_copy:
        print(f"  view properties holding copy as String (verify each): {len(string_typed_copy)}")
        for entry in string_typed_copy:
            print(f"    {entry}")

    return 1 if missing_keys else 0


def audit(language):
    status = 0
    for root, catalogue_path in TARGETS.items():
        if not os.path.isdir(root):
            continue
        print(f"=== {root}")
        status |= audit_target(root, catalogue_path, language)
    return status


if __name__ == "__main__":
    sys.exit(audit(sys.argv[1] if len(sys.argv) > 1 else "de"))
