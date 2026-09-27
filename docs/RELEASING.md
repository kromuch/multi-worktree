# Releasing MultiWorktree

Run every step from the repository root in one Terminal window, with Xcode 27 or newer.

Before the first release:

- Log in the GitHub CLI: `gh auth login`.
- Enable the version hook for this clone: `git config core.hooksPath .githooks`.
- In **System Settings → Privacy & Security**, allow your terminal app under **Automation → Finder**
  (DMG window layout) and **Screen Recording** (README screenshots). Without Finder automation the
  DMG keeps Finder's default layout; without Screen Recording the screenshots come out blank.

1. Read the version. Development has already bumped it: the pre-commit hook requires one bump for
   everything not yet on `main`. For a bigger release, first run `./app/scripts/bump-version.sh minor`
   (or `major`). The version must be newer than the latest published release:

   ```bash
   VERSION="$(sed -n 's/.*version = "\(.*\)".*/\1/p' app/Sources/MWTKit/KitInfo.swift)"
   echo "Releasing $VERSION"
   gh release view --json tagName --jq .tagName || echo "No release yet"
   swift test --package-path app
   ```

2. If the UI or the DMG look changed, refresh the README images from a throwaway build and review
   `docs/images/`:

   ```bash
   ./app/scripts/make-dmg.sh && ./app/scripts/screenshots.sh --dmg
   ```

3. Commit what steps 1–2 changed (a minor or major bump, new images), if anything; the hook checks
   the version. The working tree must be clean afterwards:

   ```bash
   git add app/Sources/MWTKit/KitInfo.swift docs/images
   git diff --cached --quiet || git commit -m "chore: release v$VERSION"
   git status --short
   ```

4. Build the release DMG from that commit:

   ```bash
   if [ -n "$(git status --porcelain)" ]; then echo "Commit or stash your changes first."; else ./app/scripts/make-dmg.sh; fi
   ```

   Output: `app/.build/dist/MultiWorktree-$VERSION.dmg` and `MultiWorktree-$VERSION.dmg.sha256`.

5. Check a simulated download. This step blocks the release: do not tag until it passes.
   From the second release on, first keep a copy of the version you have installed, for step 8:
   `ditto /Applications/MultiWorktree.app /tmp/mwt-previous.app`.

   ```bash
   cp "app/.build/dist/MultiWorktree-$VERSION.dmg" /tmp/mwt-download.dmg
   xattr -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;" /tmp/mwt-download.dmg
   open /tmp/mwt-download.dmg
   ```

   Drag the app to Applications, replacing the old one, and open it. macOS must block it; then
   **System Settings → Privacy & Security → Open Anyway** must start it. If you can, repeat on a
   second macOS user account without Homebrew and confirm the Command Line Tools banner or a working
   Apple git.

   The Intel slice: ideally someone on an Intel Mac with macOS 26 installs the DMG and opens the app.
   Otherwise, with Rosetta installed (`softwareupdate --install-rosetta`), run
   `arch -x86_64 /Applications/MultiWorktree.app/Contents/MacOS/MultiWorktree` and check that the
   menu-bar icon appears (Rosetta is an approximation of a real Intel Mac, not a substitute).

6. Tag and push:

   ```bash
   git tag -a "v$VERSION" -m "MultiWorktree $VERSION"
   git push origin main "v$VERSION"
   ```

7. Publish the release with the DMG, the checksum and install notes above the generated changelog:

   ```bash
   cat > app/.build/dist/notes.md <<'NOTES'
   ## Install

   Download the `.dmg`, open it and drag **MultiWorktree** to **Applications**.
   Requires macOS 26 or newer; universal (Apple Silicon and Intel).

   ## First launch

   MultiWorktree is ad-hoc signed and not notarized, so macOS blocks the first launch of every
   downloaded version. Open the app, click **Done**, then go to
   **System Settings → Privacy & Security** and click **Open Anyway**.
   Or run `xattr -dr com.apple.quarantine /Applications/MultiWorktree.app`.

   To verify the download, put the `.dmg` and the `.sha256` file in one folder and run
   `shasum -a 256 -c MultiWorktree-*.dmg.sha256`.
   NOTES
   gh release create "v$VERSION" --verify-tag \
     "app/.build/dist/MultiWorktree-$VERSION.dmg" \
     "app/.build/dist/MultiWorktree-$VERSION.dmg.sha256" \
     --title "MultiWorktree $VERSION" \
     --notes "$(cat app/.build/dist/notes.md)" --generate-notes
   ```

   `--generate-notes` appends GitHub's list of changes below these notes. Without the CLI: draft a
   release for the tag on GitHub, attach the two files and paste the notes.

8. From the second release on, check that the previous version announces this one: quit
   MultiWorktree, run `open /tmp/mwt-previous.app` and wait for the blue
   "MultiWorktree $VERSION is available" banner; **Download** must open the release page. Quit it,
   delete `/tmp/mwt-previous.app` and open `/Applications/MultiWorktree.app` again.
