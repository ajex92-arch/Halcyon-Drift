"""Put the text of release_notes/<tag>.md at the end of a GitHub Release's body.

Used by .github/workflows/release_notes.yml (standard library only, so it also
runs on a plain computer for a dry run):

    python3 release_notes.py <tag> <notes file> <current body file> <new body file>

It writes the new body and prints one word:
    APPENDED   the body did not have the notes yet; they are added at the end
    REPLACED   the body had an older version of the notes; it is replaced
    ADOPTED    the same text was already pasted at the end by hand; only the
               marker is added, so the page looks the same
    UNCHANGED  the body already has these notes; nothing to do

The notes section starts at a hidden marker line and runs to the end of the
body, so it is always the last part of the page: everything before the marker
(the release job's text and GitHub's change list) is kept as it is.
Exit code 1 (with the reason on stderr) when it cannot be done safely.
"""

import re
import sys

# A tag like v0.2.1 or v0.3.0-rc1. The workflow only passes names of files in
# release_notes/, but the name is checked anyway before it is used anywhere.
TAG_RE = re.compile(r"v[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.]+)?")
# GitHub refuses a release body longer than this many characters.
MAX_BODY = 125000


def fail(reason):
    sys.stderr.write("release_notes: " + reason + "\n")
    sys.exit(1)


def read_text(path):
    """The file's text with Windows line ends made plain. utf-8-sig drops a
    byte-order mark at the start (some Windows editors and PowerShell write one),
    which would otherwise stop the text from matching and break a first heading."""
    with open(path, encoding="utf-8-sig") as f:
        return f.read().replace("\r\n", "\n")


def marker_for(tag):
    """The hidden line that starts the notes section (not shown on the page)."""
    return "<!-- release-notes-workflow: release_notes/%s.md (edit that file, not this section) -->" % tag


def find_lines(haystack, needle):
    """Where the lines of needle first appear, one after another, in haystack (-1 if nowhere)."""
    n = len(needle)
    for i in range(len(haystack) - n + 1):
        if haystack[i:i + n] == needle:
            return i
    return -1


def compose(tag, notes, current):
    """Return (status, new body) for these notes and the current body."""
    notes = notes.strip()
    if not notes:
        fail("release_notes/%s.md is empty" % tag)
    marker = marker_for(tag)
    if "release-notes-workflow:" in notes:
        fail("release_notes/%s.md contains the marker text" % tag)
    section = marker + "\n" + notes + "\n"
    body = current.rstrip()
    body_lines = body.split("\n") if body else []

    # The marker counts only as a whole line of its own (the last one, if there
    # are several), so the same words inside other text, such as a pull request
    # title in GitHub's change list, never cut the body there.
    marks = [i for i, line in enumerate(body_lines) if line.strip() == marker]
    if marks:
        before = "\n".join(body_lines[:marks[-1]]).rstrip()
        new = (before + "\n\n" + section) if before else section
        status = "UNCHANGED" if new.rstrip() == current.rstrip() else "REPLACED"
        return status, new

    # Lines are compared ignoring spaces at line ends.
    plain = [line.rstrip() for line in body_lines]
    note_lines = [line.rstrip() for line in notes.split("\n")]
    n = len(note_lines)

    # The same text already pasted by hand at the end of the body: add the
    # marker in front of it, so the page stays the same and later edits of the
    # file replace it.
    if len(plain) >= n and plain[-n:] == note_lines:
        before = "\n".join(body_lines[:-n]).rstrip()
        new = (before + "\n\n" + section) if before else section
        return "ADOPTED", new

    # Pasted by hand but not at the end (something was added after it): adding
    # the notes again would show them twice, so stop and let a person decide.
    if find_lines(plain, note_lines) >= 0:
        fail("the %s notes are already in the body but not at its end; fix the release page by hand" % tag)

    new = (body + "\n\n" + section) if body else section
    return "APPENDED", new


def main(argv):
    if len(argv) != 5:
        fail("usage: release_notes.py <tag> <notes file> <current body file> <new body file>")
    tag, notes_path, current_path, out_path = argv[1:]
    if not TAG_RE.fullmatch(tag):
        fail("not a release tag name: %r" % tag)
    status, new = compose(tag, read_text(notes_path), read_text(current_path))
    if len(new) > MAX_BODY:
        fail("the new %s body has %d characters; GitHub allows %d" % (tag, len(new), MAX_BODY))
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(new)
    print(status)


if __name__ == "__main__":
    main(sys.argv)
