#!/usr/bin/env python3
"""PreToolUse hook: hard-block any tool call that references a `private/` directory.

Rationale: `~/Projects/private/` holds real personal data (the ARX export and an NWI
user dump). Tool output is transmitted to the model, so reading those files exposes
them. Permission deny rules cover the Read and file-editing tools but NOT
`cat`/`grep`/`sed` run through Bash, which is how the exposure actually happened.
This hook closes that gap by inspecting the whole tool input, Bash command strings
included.

Matches `private` only when it sits next to a path separator, so a search for the C#
keyword (`grep -r "private readonly"`) is untouched while `~/Projects/private/x.xml`,
`private/x.xml` and `ls /home/peter/Projects/private` are all blocked.
"""

import json
import re
import sys

# /private not followed by a word char, or private/ not preceded by one.
# Keeps `myprivate/` and `/private_data/` out of scope - different directories.
PRIVATE_PATH = re.compile(r"/private(?![\w-])|(?<![\w-])private/")

REASON = (
    "Blocked by the block-private-paths hook: this call references a `private/` "
    "directory. Those folders hold real personal data that must not leave this "
    "machine, and tool output is sent to the model. Use the sanctioned fixture "
    "instead (e.g. `data/arx.xml`), or ask the user to run the command themselves. "
    "If a genuinely new structural fact is needed, request aggregate-only output "
    "(counts, `sort | uniq -c`, tag-name censuses) from the user rather than reading "
    "records."
)


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        # Never fail open on a malformed payload we cannot inspect.
        payload = {}

    tool_input = payload.get("tool_input", {})
    if not isinstance(tool_input, dict):
        tool_input = {}

    # Only the fields that decide WHAT A CALL REACHES are inspected. File bodies
    # ("content", "new_string", "old_string") are exempt on purpose: writing the
    # folder name into a document is not a disclosure, and scanning bodies made it
    # impossible to document this rule at all. Reading is the risk, not mentioning.
    ACCESS_FIELDS = (
        "command",        # Bash
        "file_path",      # Read / Edit / Write
        "path",           # Grep / Glob
        "notebook_path",  # NotebookEdit
        "pattern",        # Glob path patterns
        "prompt",         # Agent / Task delegation
        "cwd",
    )
    haystack = "\n".join(
        str(tool_input[f]) for f in ACCESS_FIELDS if tool_input.get(f) is not None
    )

    if PRIVATE_PATH.search(haystack):
        json.dump(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": REASON,
                },
                "systemMessage": "Blocked: tool call referenced a private/ directory.",
            },
            sys.stdout,
        )
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
