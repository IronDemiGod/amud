# amud

A ready-to-use setup of a patched **amdl** ([apple-music-downloader](https://github.com/IronDemiGod/apple-music-downloader),
a fork of [zhaarey's](https://github.com/zhaarey/apple-music-downloader)), the
**coverfix** cover-art tool, and **wrapper-lite**, the decryption service amdl needs.
Works on Linux and natively on Windows.

What the fork adds:

- **Playlists sorted into albums**: with `paths.playlist-album-folders: true`, every
  playlist track is saved in its own `Artist/Album/` folder, exactly as if you had
  downloaded that song on its own, instead of one big playlist folder.
- **Lossless covers**: when Apple refuses the original cover file (it currently always
  does), a full-size PNG is saved instead of Apple's re-compressed JPEG.
- **coverfix**: re-downloads the covers of an existing library and replaces the
  pictures embedded in its `.flac` and `.m4a` files.
- **`amdl --update`** updates from this repo's releases.

> Use this only with content you are entitled to access, and in line with Apple's
> terms and the law where you live. You need an Apple ID with an active Apple Music
> subscription.

## Install

Three parts: amdl (+ coverfix), wrapper-lite, and a config file.

### 1. Download amdl and coverfix

Get them from the **[latest release](https://github.com/IronDemiGod/amud/releases/latest)**:

| Your computer | amdl | coverfix |
|---|---|---|
| Windows (most PCs) | `amdl_windows_amd64.exe` | `coverfix_windows_amd64.exe` |
| Windows on ARM | `amdl_windows_arm64.exe` | `coverfix_windows_arm64.exe` |
| Linux (most PCs) | `amdl_linux_amd64` | `coverfix_linux_amd64` |
| Linux ARM | `amdl_linux_arm64` | `coverfix_linux_arm64` |
| Mac, Apple Silicon | `amdl_darwin_arm64` | `coverfix_darwin_arm64` |
| Mac, Intel | `amdl_darwin_amd64` | `coverfix_darwin_amd64` |

Put both in one folder (for example `C:\amdl` or `~/amdl`) and rename them to
`amdl.exe` / `coverfix.exe` (Windows) or `amdl` / `coverfix` (Linux, Mac). On Linux
and Mac also make them executable:

```bash
chmod +x amdl coverfix
```

Optional: [ffmpeg](https://ffmpeg.org/download.html), only needed if you want amdl to
convert downloads (e.g. to FLAC).

### 2. Start wrapper-lite

amdl does not decrypt anything itself; it asks wrapper-lite, which has to be running
and logged in to your Apple ID while you download. It listens on
`http://127.0.0.1:12340`. Pick one way to run it:

| | Native | QEMU (small VM) | Docker |
|---|---|---|---|
| **Linux** | **recommended**: no VM, no root, runs in the background | works (KVM) | works |
| **Windows** | – | **recommended**: a normal program | Docker Desktop (not tested here) |
| **Mac** | – | works (not tested here) | Docker Desktop |

Ready-made wrapper packages are on the
[wrapper-lite build runs](https://github.com/WorldObservationLog/wrapper/actions/workflows/build-lite.yml?query=branch%3Alite+is%3Asuccess)
page (sign in to GitHub, open the newest run, download the artifact named below), or
build them yourself on Linux with Docker: `scripts/build-wrapper-win.sh` from this repo
builds every variant into the `wrapper/` submodule (see [Build from source](#build-from-source)).

Whatever you choose, keep the service on `127.0.0.1`: it has no password, and anyone who
can reach the port can use your account.

<details open>
<summary><b>Linux: native</b> (recommended)</summary>

Runs Apple's Android code directly, in an unprivileged user namespace: no Docker, no
VM, no root. `scripts/wrapper-linux.sh` from this repo installs it with a small
`wrapper` command next to it.

1. Get the package **`wrapper-lite-linux-x86_64`** and unzip it, e.g. to
   `~/Downloads/wrapper-lite-linux-x86_64` (or build it, see above).
2. Install it, e.g. into `~/amdl` (the folder where amdl lives):
   ```bash
   git clone https://github.com/IronDemiGod/amud && cd amud
   scripts/wrapper-linux.sh install ~/amdl --from ~/Downloads/wrapper-lite-linux-x86_64
   # self-built instead: scripts/wrapper-linux.sh install ~/amdl
   ```
3. Log in once. It asks for your Apple ID, the password (hidden) and, with two-factor
   authentication, the code Apple shows you:
   ```bash
   ~/amdl/wrapper login
   ```
4. Start it in the background whenever you want to download:
   ```bash
   ~/amdl/wrapper            # same as: ~/amdl/wrapper start
   ~/amdl/wrapper status     # running?   ~/amdl/wrapper log   follow the log
   ~/amdl/wrapper stop
   ```

The login is stored in `~/amdl/wrapper-lite/rootfs/data`, readable only by you. Running
`install` again updates the program and keeps the login. `WRAPPER_PORT=12341 ~/amdl/wrapper`
uses another port.

If `start` fails with `unshare: Operation not permitted`, your system blocks
unprivileged user namespaces (Ubuntu 23.10 and later do by default through AppArmor).
Either allow them (`sudo sysctl kernel.apparmor_restrict_unprivileged_userns=0`, add it
to `/etc/sysctl.d/` to keep it), or use QEMU or Docker below.
</details>

<details>
<summary><b>Linux: QEMU</b></summary>

Boots a tiny VM; fast with KVM (being in the `kvm` group is enough). Get the package
**`wrapper-lite-qemu-linux-x86_64`** (it includes QEMU), or after
`scripts/build-wrapper-win.sh` use the `wrapper/` folder with the system's
`qemu-system-x86_64`:

```bash
cd ~/amdl/wrapper-lite-qemu
./wrapper-lite-qemu --login 'you@example.com:your-apple-id-password'   # once; asks for the 2FA code
./wrapper-lite-qemu                                                    # start; Ctrl+C stops it
```

The login is kept in `qemu/data.img`. The VM's port is forwarded to `127.0.0.1` only.
</details>

<details>
<summary><b>Linux: Docker</b></summary>

The first start logs in and stores the login in `wrapper-data/`:

```bash
mkdir -p ~/amdl/wrapper-data && cd ~/amdl
docker run -d --name wrapper-lite --privileged --restart unless-stopped \
  -p 127.0.0.1:12340:12340 -v "$PWD/wrapper-data:/app/rootfs/data" \
  -e USERNAME='you@example.com' -e PASSWORD='your-apple-id-password' \
  ghcr.io/worldobservationlog/wrapper-lite:latest
docker logs -f wrapper-lite
```

If your Apple ID uses two-factor authentication, the log says `Enter your 2FA code
into …/2fa.txt`. Within 10 minutes, write the code Apple shows you into
`wrapper-data/2fa.txt` (as root: the folder belongs to the container), e.g.
`echo 123456 | sudo tee ~/amdl/wrapper-data/2fa.txt`.

Once the log says `wrapper-lite listening`, it is ready. The login is cached, so to
get rid of the password in the container settings, recreate it without it, and make
the stored login readable only by root:

```bash
docker rm -f wrapper-lite
docker run -d --name wrapper-lite --privileged --restart unless-stopped \
  -p 127.0.0.1:12340:12340 -v "$PWD/wrapper-data:/app/rootfs/data" \
  ghcr.io/worldobservationlog/wrapper-lite:latest
sudo chmod -R go-rwx ~/amdl/wrapper-data
```
</details>

<details open>
<summary><b>Windows: QEMU</b> (recommended, no Docker or WSL)</summary>

wrapper-lite runs Apple's Android code, so on Windows it starts a tiny Linux VM
through QEMU. You start it like a normal program.

1. **Turn on Windows Hypervisor Platform** once (PowerShell as administrator, then
   reboot). Without it the VM runs in slow software emulation.
   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform
   ```
2. **Get the package** **`wrapper-lite-qemu-windows-x86_64`** (~150 MB), or build it
   with `scripts/build-wrapper-win.sh`; that self-built package also has `login.bat`
   and `start-wrapper.bat`. Unzip it, e.g. to `C:\amdl\wrapper-lite`.
3. **Log in once**, in PowerShell in that folder (type the 2FA code when asked):
   ```powershell
   .\wrapper-lite-qemu.exe --login "you@example.com:your-apple-id-password"
   ```
   It stores the login and exits. (Self-built package: run `login.bat`.)
4. **Start it** whenever you want to download, and keep the window open:
   ```powershell
   .\wrapper-lite-qemu.exe --smp 1 --memory 512
   ```
   (Self-built package: `start-wrapper.bat`.)
</details>

<details>
<summary><b>Windows: Docker</b> (Docker Desktop)</summary>

With Docker Desktop (WSL 2 backend), the Linux Docker commands work in PowerShell with
Windows paths. Not tested with this fork.

```powershell
mkdir C:\amdl\wrapper-data; cd C:\amdl
docker run -d --name wrapper-lite --privileged --restart unless-stopped `
  -p 127.0.0.1:12340:12340 -v "${PWD}\wrapper-data:/app/rootfs/data" `
  -e USERNAME='you@example.com' -e PASSWORD='your-apple-id-password' `
  ghcr.io/worldobservationlog/wrapper-lite:latest
docker logs -f wrapper-lite
```

For a 2FA code, write it into `C:\amdl\wrapper-data\2fa.txt` within 10 minutes. Once
the log says `wrapper-lite listening`, recreate the container without `-e USERNAME` and
`-e PASSWORD`, as on Linux.
</details>

<details>
<summary><b>Mac</b></summary>

Use Docker Desktop with the Linux Docker commands, or the QEMU package
**`wrapper-lite-qemu-macos-aarch64`**: `./wrapper-lite-qemu --login "email:password"`,
then `./wrapper-lite-qemu`. Not tested with this fork.
</details>

Check that it is up: open <http://127.0.0.1:12340/status> in a browser (or
`curl http://127.0.0.1:12340/status`). It should answer with `"msg":"SUCCESS"`.

### 3. First run and config

Open a terminal in the amdl folder and run amdl once without anything after it. It
creates `config.yaml` in the folder you run it from (and says it needs a URL):

```bash
./amdl                 # Windows: .\amdl.exe
```

Always start amdl from that folder, so it finds its `config.yaml`. `./amdl --help`
lists all options.

Edit `config.yaml`. The settings that matter most:

```yaml
general:
  lite-server: "http://127.0.0.1:12340"   # where wrapper-lite runs
  parallel-downloads: 3                   # tracks downloaded at once (see "Speed" below)

paths:
  alac: 'C:\Music'                        # where lossless downloads go (Linux: '/home/you/Music')
  atmos: 'C:\Music\Atmos'                 # Dolby Atmos downloads (--atmos)
  aac: 'C:\Music\AAC'                     # AAC downloads (--aac)
  playlist-album-folders: true            # sort playlist tracks into Artist/Album folders
  work-dir: "auto"                        # where tracks are processed before they are saved

metadata:
  artwork:
    format: "original"                    # original file, or full-size PNG if Apple refuses it
    embed: true                           # also embed the cover in every track

convert:
  after-download: false                   # true + format: "flac" to convert (needs ffmpeg)
  parallel: 0                             # conversions at once; 0 = automatic
```

**Speed.** One download from Apple runs at roughly 100-250 Mbit/s, so several at once
fill a fast connection:

- `parallel-downloads`: 3 is a good start; 5 on a fast PC with gigabit, 2 on a laptop
  with 2 cores (converting to FLAC is then the limit, not the network). 1 downloads one
  track after another.
- `work-dir: "auto"`: tracks are downloaded and processed in memory (RAM on Linux; on
  Windows files Windows keeps in memory), and only the finished file is written to the
  save folder. This matters most when the save folder is slow (a USB or network drive).
  `""` turns it off; a folder name uses that folder.
- `convert.parallel`: FLAC conversions at once, each using one CPU core; automatic is
  one per three CPU threads (2 to 6).

On Windows, write paths in **single quotes**: inside double quotes `\U`, `\t` and
the like are escape sequences and break the file.

Everything else is explained in the comments of `config.yaml` and in
[upstream's documentation](https://github.com/IronDemiGod/apple-music-downloader#readme).

### 4. Download

With wrapper-lite running, in the amdl folder:

```bash
./amdl "https://music.apple.com/us/album/…"         # an album
./amdl "https://music.apple.com/us/song/…"          # one song
./amdl "https://music.apple.com/us/playlist/…"      # a playlist
./amdl --select "https://music.apple.com/us/album/…"   # choose tracks
./amdl --atmos "https://music.apple.com/us/album/…"    # Dolby Atmos
./amdl --search song "never gonna give you up"         # search
```

On Windows use `.\amdl.exe` instead of `./amdl`. Already downloaded tracks are skipped.

In a terminal, an album or playlist shows live bars, like coverfix: songs done, failures
and the total speed, an overall bar with the time left, and one bar per track being
downloaded or processed (quality, size, speed, or the step it is on). Finished, failed and
already downloaded (skipped) tracks keep their bar for a few seconds. Tracks that failed
are listed with the reason at the end. `--no-live` prints plain lines instead.
`--timings` adds a summary of how long each step took and the overall speed, useful to
tune the speed settings above.

A run that is stopped halfway (Ctrl+C, a crash) leaves no half-finished files: tracks
are only given their final name when they are complete, so the next run simply
downloads the missing ones.

### 5. Fix covers of an existing library (optional)

```bash
./coverfix --help
./coverfix --cover png --embed jpg3000 -n "C:\Music"   # preview: shows what it would do
./coverfix --cover png --embed jpg3000 "C:\Music"      # do it
./coverfix --embed png "C:\Music"                     # only the embedded pictures
./coverfix --cover png "C:\Music"                     # only the cover files
```

`--cover` is the `cover.*` file saved in each album folder and `--embed` the picture put
into every track: `jpg` or `png`, optionally with a size, e.g. `png`, `jpg3000`, `png5000`.
Give one or both: the part you leave out is not touched. Without a size you get the
largest Apple has.

```bash
./coverfix --embed png --in "C:\Music" "ADO,Pink Floyd,King Gnu"   # some artists in one folder
./coverfix --embed png --parallel 8 "C:\Music"                    # 8 albums at once (default 4)
```

`--in FOLDER` takes the names after it as folders inside FOLDER, separated by commas or
spaces (album folders work too, e.g. `"ADO/Vivarium - Single"`). In a terminal coverfix
shows live bars: albums done, time left, and one bar per album in progress; albums with
problems are listed at the end. `--no-live` prints a line per album instead. coverfix works on folders made by amdl
(it reads the album from the tracks' tags) and only changes pictures, never tags or audio.

### Updating

```bash
./amdl --update        # installs the latest release from this repo
```

coverfix: download the new file from the [releases](https://github.com/IronDemiGod/amud/releases).

## Troubleshooting

| Problem | Fix |
|---|---|
| `connection refused` / `lite-server` errors | wrapper-lite isn't running, or not on the address in `general.lite-server`. Check <http://127.0.0.1:12340/status>. |
| `load Config failed … found unknown escape character` | a Windows path in double quotes; use single quotes: `alac: 'C:\Music'`. |
| `Access is denied` when saving | the save folder belongs to another Windows user, or Windows Security's *Controlled folder access* blocks amdl. Pick a folder of your own or allow `amdl.exe` there. |
| wrapper-lite on Windows is extremely slow | Windows Hypervisor Platform is off (step 2.1). |
| coverfix skips a folder | it holds tracks of several albums, or a playlist folder (album artist "Apple Music"). |
| `"C:\Folder\"` arrives with a stray `"` | Windows quoting: leave off the trailing backslash. |

## Build from source

This repo is a workspace: build scripts and these notes, with the two source trees as
**git submodules** (separate repos, pinned to exact commits).

```bash
git clone --recurse-submodules https://github.com/IronDemiGod/amud
cd amud
scripts/build-amdl.sh               # needs Go 1.23+; builds into ../amud-work/dist and sets up ../amud-work/run
scripts/build-wrapper-win.sh        # needs Docker; builds ../amud-work/dist/wrapper-lite-win (first run ~1 GB of downloads)
scripts/deploy-windows.sh <folder>  # copy the newest release build (or --local; --wrapper adds the wrapper package)
scripts/wrapper-linux.sh install <folder>   # install the native Linux wrapper-lite (see step 2 above)
```

`build-wrapper-win.sh` builds everything inside a throwaway Ubuntu container, boots the
VM once as a test, and adds QEMU for Windows. It also leaves the Linux builds in the
`wrapper/` submodule folder: the native `wrapper-lite-rootless` with `rootfs/` (what
`wrapper-linux.sh install` takes) and `wrapper-lite-qemu` with `qemu/`. On Linux, `../amud-work/run/` then holds a
`config.yaml` and links to the builds: `cd ../amud-work/run && ./amdl <url>`.

Everything the scripts produce goes to `amud-work/` next to the repo, so the repo folder
stays identical to what is on GitHub. Set `AMUD_WORK=/some/folder` to use another place.

```
amud/
├── apple-music-downloader/   submodule: the amdl fork, branch main
├── wrapper/                  submodule: WorldObservationLog/wrapper, branch lite (unmodified)
└── scripts/                  build-amdl.sh, build-wrapper-win.sh, deploy-windows.sh, release.sh, wrapper-linux.sh

amud-work/                    next to the repo, not in git (AMUD_WORK to move it)
├── dist/                     build outputs
├── run/                      config + links to the Linux builds
└── cache/                    build downloads
```

## Development

After a fresh clone the submodules sit on a bare commit ("detached HEAD"): run
`git checkout main` (amdl) or `git checkout lite` (wrapper) before changing them.

**Two-commit rule:** commit and **push** inside `apple-music-downloader/` first, then
commit the moved bookmark in this repo (`git status` shows it as `new commits`) and push.

**Update from upstream:**

```bash
cd apple-music-downloader
git remote add upstream https://github.com/zhaarey/apple-music-downloader.git   # once
git fetch upstream
git rebase upstream/main main
git push --force-with-lease origin main
cd .. && git commit -am "Bump amdl" && git push
```

**Release:** `scripts/release.sh v0.1.4.3` builds all platforms and publishes them as a
release of **this repo (amud)**, not the fork (`--dry-run` to only build). The tag goes on
amud's current commit, and the binaries have amud built in as their `--update` source.
Releases before v0.1.4.2 were on the fork; v0.1.4.1 was removed, so its binaries cannot
`--update` (replace them by hand). Tags are `v<upstream version>.<fork revision>`;
after rebasing onto upstream v0.1.5 the next one is `v0.1.5.1`. The wrapper-lite
package is not released: it contains Apple's proprietary libraries and GPL'd QEMU
binaries; build it with `build-wrapper-win.sh`.

GitHub Actions are off on the fork: upstream's workflows would release on every push to `main`.

## What is changed in amdl

- **`paths.playlist-album-folders: true`**: each selected playlist track is resolved to
  its album and downloaded through the normal album path, into `Artist/Album/` with the
  album's cover and tags. Tracks are grouped by album, so download order follows albums.
  Music videos in a playlist go to the MV folder. The optional `.m3u8` playlist file goes
  into the format folder.
- **Covers**: `artwork.format` defaults to `"original"`. Apple answers 403 for the
  source-file URL (`a5.mzstatic.com/us/r1000/0/…`, every album tested in Nov 2026), so
  amdl then saves a full-size PNG (lossless, ~10-15 MB) instead of Apple's re-encoded
  JPEG, and removes a stale `cover.jpg`. With `artwork.embed: true` that PNG is also
  embedded in every track.
- **Windows folder creation**: `fsutil.MkdirAll` accepts parent folders Windows reports
  as existing but refuses to stat, so the real error is shown.
- **coverfix** (`cmd/coverfix`): finds each album by iTunes album ID (.m4a), else UPC,
  else ISRC + album name (amdl's FLAC conversion drops the album ID). FLAC pictures are
  rewritten in place with the audio copied untouched. FLAC caps a picture at 16 MB, so
  too-large ones are retried as PNG 5000 → 4000 → … → 1000.
  Up to 4 albums are processed at once (`--parallel N`), from all given folders together
  (several artist folders share the slots), each album's messages printed as one block in
  folder order. In a terminal, only live bars are shown: an overall bar
  (albums done, failures, time left) and one bar per album in progress (tracks embedded,
  current step); messages of albums with problems are printed when it is done.
  `--no-live` prints every album's result instead.
  `--in FOLDER` takes the folder arguments as names inside FOLDER, comma-separated
  allowed: `coverfix --cover png --embed png --in "C:/Users/Admin/Music" "ADO,Pink Floyd"`.
- **Background processing**: once a track is downloaded, the next download starts right
  away; defrag, alac-fix, tagging and the optional ffmpeg conversion run on two
  background workers. Their messages are printed between tracks (`[background] …`), in
  track order; amdl waits for them before writing an `.m3u8` and before the final summary.
  ffmpeg runs at lower priority (Windows "below normal", nice 10 elsewhere), so on a
  machine with few cores it yields the CPU to the download; its output is unchanged.
- **Parallel downloads**: `general.parallel-downloads: 3` downloads three tracks at once
  (default 1: one after another, as before). A single download from Apple's servers
  stays far below a fast connection (~100-140 Mbit/s on gigabit Ethernet in tests).
  Each download runs in a child amdl process (`--download-worker`, hidden) with the same,
  unchanged download code; its progress bar is discarded, and amdl prints one line per
  track instead (`Downloaded 41.2 MB at 13.5 MB/s = 108 Mbit/s`). The request, config
  and tokens included, goes to the child over stdin, never on its command line. At most
  ffmpeg conversions run at once per three CPU threads (2 to 6: 2 on a 4-thread laptop,
  4 on a 12-thread PC; `convert.parallel` sets it, 0 = this automatic rule); each
  conversion's settings and output are unchanged. amdl waits for earlier tracks before showing a
  `--select` prompt.
- **Live progress list**: in a terminal, an album or playlist is shown as a list that
  redraws in place (like `docker pull`), two lines per track: number, title, artist and
  quality (e.g. `ALAC 24-bit/96 kHz`), then a bar with %, size and speed, or the step
  (processing, converting), `✔ done` or `✖` with the reason. The header shows the tracks
  done and the combined download speed. A long list folds its finished tracks into one
  line so it always fits the window. Progress is read from the download worker's
  progress bar output; the download code is unchanged. Messages of failed tracks are
  printed after the list. Plain output with `--no-live`, `--debug`, `--json`, when the
  output is not a terminal, or when the list contains music videos.
  Frames are drawn with the cursor hidden and as one synchronized update, so they don't
  flicker over SSH; messages that would land under the list are kept for failed tracks.
- **Work folder (`paths.work-dir`, default `"auto"`)**: tracks are downloaded and
  processed (defrag, alac-fix, tags, FLAC) in a work folder, and only the finished file is
  moved to the save folder. `"auto"` uses RAM (`/dev/shm/amdl`) on Linux; on Windows a
  hidden `.amdl-work` folder in the save folder whose files carry the temporary attribute,
  so Windows keeps them in memory and, being on the same drive, the finished file is moved
  by a rename: only it is written to disk (defrag skips its sync for such files; the tag
  library's own short-lived temp copy is the one file outside amdl's control). Elsewhere
  it works in the save folder; `""` always uses the save folder; any other value is a folder (a fast
  SSD, or a RAM disk like `R:/amdl` on Windows). On a slow save folder this saves several
  full rewrites per track: a hi-res album on a USB NTFS drive (ntfs-3g) spent most of its
  time there. Moves across drives go through a `.part` name. A track falls back to the
  save folder when the work folder has less than ~512 MB per track in progress free. Each
  run uses its own subfolder, removed at the end; folders of killed runs are removed by
  the next run.
- **Safe file names while working**: a track is downloaded to `Song.part.m4a` and ffmpeg
  writes `Song.part.flac`; each is renamed only when complete, so a run stopped halfway
  never leaves a file the next run would skip as "already exists". An `.m4a` left
  without its converted file is converted on the next run.
- **`--timings`**: prints how long each stage of every track took and a summary: download
  and lyrics in the foreground, defrag, alac-fix, tags and convert in the background,
  the time spent waiting for the background work, and the wall time.

## Credits and licenses

- amdl: [zhaarey/apple-music-downloader](https://github.com/zhaarey/apple-music-downloader)
  and its contributors (original script by Sorrow). Upstream has no license file.
- wrapper-lite: [WorldObservationLog/wrapper](https://github.com/WorldObservationLog/wrapper), MIT License.
- QEMU (bundled in the Windows wrapper package): GPL v2, builds from [qemu.weilnetz.de](https://qemu.weilnetz.de/).
- This repo's own files (scripts and notes): [MIT License](LICENSE). It does not cover
  the submodules, which keep their own terms.
- This repo's scripts and notes, and the fork's changes, were written with the help of Claude.
