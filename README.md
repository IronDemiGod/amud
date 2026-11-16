# amud

A workspace for a patched **amdl** (Apple Music downloader), **coverfix**
(cover-art tool) and **wrapper-lite** (the decryption backend amdl needs), on
Linux and natively on Windows.

This repo holds the build scripts and these notes. The two source trees are
**git submodules**: full repos of their own, of which this repo records the
exact commit to use.

```bash
git clone --recurse-submodules https://github.com/IronDemiGod/amud
# already cloned without it?  git submodule update --init
```

After a fresh clone the submodules sit on a bare commit ("detached HEAD"):
run `git checkout main` (amdl) or `git checkout lite` (wrapper) before
changing anything in them.

## Layout

```
amud/
├── apple-music-downloader/   submodule: patched amdl, branch `main`
│                             remotes: origin = this fork, upstream = zhaarey/apple-music-downloader
├── wrapper/                  submodule: WorldObservationLog/wrapper, branch `lite` (unmodified)
├── scripts/
│   ├── build-amdl.sh         test + build amdl and coverfix → dist/linux, dist/windows; sets up run/
│   ├── build-wrapper-win.sh  build the native-Windows wrapper package → dist/wrapper-lite-win
│   └── deploy-windows.sh     copy the Windows builds to a folder Windows can reach
├── dist/                     build outputs                                [not in git]
├── run/                      config.yaml + links to the Linux builds      [not in git]
└── .cache/                   build downloads (busybox deb, QEMU installer) [not in git]
```

Personal data never goes into git: `run/` (config), `dist/`, `.cache/` and any
wrapper data folder (`rootfs/`) are ignored.

## Build

```bash
scripts/build-amdl.sh                   # ~1 min; also creates run/ on first use
scripts/build-wrapper-win.sh            # needs Docker; a few minutes (first run downloads the Android NDK)
scripts/deploy-windows.sh <folder>      # e.g. a folder on a drive shared with Windows
```

`build-wrapper-win.sh` builds everything inside a throwaway Ubuntu container
and boots the guest once as a smoke test before packaging it.

## Use

amdl needs wrapper-lite running and reachable at `http://127.0.0.1:12340`
(`general.lite-server` in `config.yaml`).

**Linux**: run wrapper-lite with its Docker image or its QEMU launcher (see
`wrapper/README.md`), set your music folder in `run/config.yaml`, then:

```bash
cd run
./amdl "https://music.apple.com/…/album/…"
./coverfix --help
```

**Windows**: in the deployed folder, run `wrapper-lite\login.bat` once, then
`wrapper-lite\start-wrapper.bat` (keep it open), then `amdl.exe <url>`.
Enable "Windows Hypervisor Platform" first, or QEMU falls back to slow
software emulation. In `config.yaml`, write Windows paths in single quotes:
`alac: 'C:\Music'`.

Do **not** run `amdl --update`: it replaces this build with the upstream
release, which lacks these changes.

## Changing code (the two-commit rule)

1. Commit **and push** inside the submodule (`apple-music-downloader/`).
   Push it first: a bookmark to an unpushed commit breaks fresh clones.
2. In the top folder, `git status` shows `modified: apple-music-downloader
   (new commits)`; commit that to move the bookmark, then push.

## Update from upstream

```bash
cd apple-music-downloader
git fetch upstream
git rebase upstream/main main          # resolve conflicts if any, then scripts/build-amdl.sh
git push --force-with-lease origin main
cd .. && git commit -am "Bump amdl" && git push
```

Wrapper: `cd wrapper && git pull origin lite`, run `scripts/build-wrapper-win.sh`,
then commit the moved bookmark.

## What is changed in amdl

- **`paths.playlist-album-folders: true`**: playlist tracks go to their own
  `Artist/Album/` folders, like a single-song download, instead of one
  `Apple Music/<Playlist>/` folder. Tracks are grouped by album, so download
  order follows albums. Music videos in a playlist go to the MV folder.
- **Windows folder creation**: `fsutil.MkdirAll` accepts parent folders Windows
  reports as existing but refuses to stat, so the real error (e.g. "Access is
  denied") is shown instead of "Cannot create a file when that file already exists".
- **Covers**: `artwork.format` defaults to `"original"`. Apple answers 403 for
  the source-file URL (`a5.mzstatic.com/us/r1000/0/…`, every album tested in
  Nov 2026), so amdl then saves a **full-size PNG** (lossless, ~10-15 MB)
  instead of Apple's re-encoded JPEG, and removes a stale `cover.jpg`. With
  `artwork.embed: true` that PNG is also embedded in every track.
- **coverfix** (`cmd/coverfix`): `--cover=` and `--embed=` (both required),
  values `jpg|png[resolution]`, e.g. `png`, `jpg3000`. Redoes `cover.*` and the
  embedded picture of every `.m4a`/`.flac` in a library. Finds each album by
  iTunes album ID (.m4a), else UPC, else ISRC + album name (amdl's FLAC
  conversion drops the album ID). FLAC pictures are rewritten in place with
  the audio copied untouched; FLAC caps a picture at 16 MB, so too-large ones
  are retried as PNG 5000 → 4000 → … → 1000. Skips playlist folders and
  folders that mix albums.
