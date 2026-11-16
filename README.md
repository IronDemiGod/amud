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
`http://127.0.0.1:12340`.

<details open>
<summary><b>Linux</b> (Docker)</summary>

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
get rid of the password in the container settings, recreate it without it:

```bash
docker rm -f wrapper-lite
docker run -d --name wrapper-lite --privileged --restart unless-stopped \
  -p 127.0.0.1:12340:12340 -v "$PWD/wrapper-data:/app/rootfs/data" \
  ghcr.io/worldobservationlog/wrapper-lite:latest
```

Keep `-p 127.0.0.1:…`: the service has no password, and publishing the port on all
interfaces would let anyone on your network use your account.
</details>

<details open>
<summary><b>Windows</b> (native, no Docker or WSL)</summary>

wrapper-lite runs Apple's Android code, so on Windows it starts a tiny Linux VM
through QEMU. You start it like a normal program.

1. **Turn on Windows Hypervisor Platform** once (PowerShell as administrator, then
   reboot). Without it the VM runs in slow software emulation.
   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform
   ```
2. **Get the wrapper-lite package** (~150 MB), either:
   - **ready-made:** sign in to GitHub, open the
     [wrapper-lite build runs](https://github.com/WorldObservationLog/wrapper/actions/workflows/build-lite.yml?query=branch%3Alite+is%3Asuccess),
     open the newest one and download the artifact **`wrapper-lite-qemu-windows-x86_64`**; or
   - **build it yourself** on any Linux machine with Docker:
     `scripts/build-wrapper-win.sh` from this repo (see [Build from source](#build-from-source)).
     That package also has `login.bat` and `start-wrapper.bat`.

   Unzip it, e.g. to `C:\amdl\wrapper-lite`.
3. **Log in once**, in PowerShell in that folder (type the 2FA code when asked):
   ```powershell
   .\wrapper-lite-qemu.exe --login "you@example.com:your-apple-id-password"
   ```
   It stores the login and exits. (With the self-built package: run `login.bat`.)
4. **Start it** whenever you want to download, and keep the window open:
   ```powershell
   .\wrapper-lite-qemu.exe --smp 1 --memory 512
   ```
   (Self-built package: `start-wrapper.bat`.)
</details>

<details>
<summary><b>Mac</b></summary>

Use Docker Desktop with the Linux commands above, or the QEMU launcher: download the
`wrapper-lite-qemu-macos-aarch64` artifact from the same
[build runs](https://github.com/WorldObservationLog/wrapper/actions/workflows/build-lite.yml?query=branch%3Alite+is%3Asuccess)
and use `./wrapper-lite-qemu --login "email:password"`, then `./wrapper-lite-qemu`.
Not tested with this fork.
</details>

Check that it is up: open <http://127.0.0.1:12340/status> in a browser. It should
answer with `"msg":"SUCCESS"`.

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

paths:
  alac: 'C:\Music'                        # where lossless downloads go (Linux: '/home/you/Music')
  atmos: 'C:\Music\Atmos'                 # Dolby Atmos downloads (--atmos)
  aac: 'C:\Music\AAC'                     # AAC downloads (--aac)
  playlist-album-folders: true            # sort playlist tracks into Artist/Album folders

metadata:
  artwork:
    format: "original"                    # original file, or full-size PNG if Apple refuses it
    embed: true                           # also embed the cover in every track

convert:
  after-download: false                   # true + format: "flac" to convert (needs ffmpeg)
```

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

### 5. Fix covers of an existing library (optional)

```bash
./coverfix --help
./coverfix --cover=png --embed=jpg3000 -n "C:\Music"   # preview: shows what it would do
./coverfix --cover=png --embed=jpg3000 "C:\Music"      # do it
```

`--cover` is the `cover.*` file saved in each album folder and `--embed` the picture put
into every track: `jpg` or `png`, optionally with a size, e.g. `png`, `jpg3000`, `png5000`.
Without a size you get the largest Apple has. coverfix works on folders made by amdl
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
scripts/build-amdl.sh               # needs Go 1.23+; builds dist/linux, dist/windows and sets up run/
scripts/build-wrapper-win.sh        # needs Docker; builds dist/wrapper-lite-win (first run ~1 GB of downloads)
scripts/deploy-windows.sh <folder>  # copy the Windows builds to a folder Windows can reach
```

`build-wrapper-win.sh` builds everything inside a throwaway Ubuntu container, boots the
VM once as a test, and adds QEMU for Windows. On Linux, `run/` then holds a
`config.yaml` and links to the builds: `cd run && ./amdl <url>`.

```
amud/
├── apple-music-downloader/   submodule: the amdl fork, branch main
├── wrapper/                  submodule: WorldObservationLog/wrapper, branch lite (unmodified)
├── scripts/                  build-amdl.sh, build-wrapper-win.sh, deploy-windows.sh, release.sh
├── dist/                     build outputs        [not in git]
├── run/                      config + links       [not in git]
└── .cache/                   build downloads      [not in git]
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

## Credits and licenses

- amdl: [zhaarey/apple-music-downloader](https://github.com/zhaarey/apple-music-downloader)
  and its contributors (original script by Sorrow). Upstream has no license file.
- wrapper-lite: [WorldObservationLog/wrapper](https://github.com/WorldObservationLog/wrapper), MIT License.
- QEMU (bundled in the Windows wrapper package): GPL v2, builds from [qemu.weilnetz.de](https://qemu.weilnetz.de/).
- This repo's own files (scripts and notes): [MIT License](LICENSE). It does not cover
  the submodules, which keep their own terms.
- This repo's scripts and notes, and the fork's changes, were written with the help of Claude.
