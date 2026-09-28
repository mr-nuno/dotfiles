## Sensitive data — `private/` folders are off limits

**Never read, open, search, copy, or reference any file under a `private/` directory.**
These hold real personal data (personal numbers, names, contact details, credential
numbers) that must not leave this machine. Tool output is transmitted to the model, so
reading such a file exposes it — there is no "just looking".

This is enforced by the harness, not by attention:

- `permissions.deny` in `~/.claude/settings.json` blocks those paths with two rules:
  `Read(**/private/**)` for reads, and `Edit(**/private/**)` for every file-editing
  tool — `Edit`, `Write` and `NotebookEdit` all match the `Edit(path)` form. There is
  no separate `Write(...)` rule form; a `Write(**/private/**)` entry matches nothing
  and Claude Code warns about it at startup.
- `~/.claude/hooks/block-private-paths.py` (a `PreToolUse` hook) blocks Bash commands,
  file tools and subagent delegation whose target references such a directory — the gap
  permission rules leave open, since `cat`/`head`/`grep`/`sed` are not the `Read` tool.

The hook matches the folder name only when it sits next to a path separator, so
searching for the C# keyword (`grep -rn "private readonly"`) is unaffected. It inspects
only the fields that decide what a call reaches — `command`, `file_path`, `path`,
`pattern`, `prompt`, `cwd` — so file bodies are exempt and documents like this one can
still be written.

### What to do instead

1. **Use the sanctioned fixture.** Sensitive datasets have a purpose-built dummy
   alongside them, created so the structure can be inspected safely — e.g.
   `identity-aspire/data/arx.xml` for the ARX XML export. Read that.
2. **If the fixture lacks something, extend the fixture** with synthetic values rather
   than reaching for the real file. That closes the gap permanently.
3. **If a fact genuinely requires the real dataset**, ask Peter to run it and paste the
   result — and request *aggregate-only* output that cannot carry a record: `grep -c`,
   `grep -o` on tag names, `sort | uniq -c` on value domains, byte and line counts.
   Never `head`, `tail`, `sed -n <range>`, or `grep -A/-B/-C`, which return whatever
   records happen to sit adjacent to the match.

### Do not launder it

Real identifiers must not be copied out of a sensitive dataset into tracked files,
commits, or summaries. Record the *shape* (`R-Ix_<10 digits>`, "a bare personnummer")
rather than the value. Counts and structure are fine to quote; individual records are
not.
