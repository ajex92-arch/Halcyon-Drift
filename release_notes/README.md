# Release page notes

One file per release, named after its tag: `v0.2.1.md` for v0.2.1. The
release-notes workflow (`.github/workflows/release_notes.yml`) adds the file's
text at the end of that tag's GitHub Release page, under the download and play
instructions and GitHub's change list.

- Add the file in the release commit, before the tag is pushed. The text appears
  about a minute after the tag's release run finishes.
- To change the text later, edit the file and push main: the section on the page
  is replaced, the rest of the page is kept.
- On the page the section starts at a hidden marker line and runs to the end.
  Edit the file, not the page: anything typed on the website below the marker
  is replaced at the next run (every main build runs it). If the marker line is
  deleted and the file changes later, the new text is added under the old one.
- Deleting a file here does not remove its text from the page.
- Write it in plain words for players: what is new, what to try, known issues.
  The full notes stay in `remake/docs/RELEASE_NOTES.md`.
- These files are public, like the rest of the repository: no personal
  information, no paths from anyone's computer, no keys or passwords.

v0.1.0 and v0.2.0 got their page text by hand, so they have no file here.
