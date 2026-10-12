# OBS Meeting Recorder — Experimental True-Portable Builder v1.0

This **separate GitHub Actions repository** builds a Windows x64 experimental OBS Studio ZIP from a **clean** OBS fork or the official OBS source. It is not an official OBS release.

## What is changed

- `libobs-d3d11/d3d11-shader.cpp` and `d3d11-subsystem.cpp`: preserve Direct3D11 shader caching, but replace both `C:\ProgramData\obs-studio\shader-cache` path lookups with a single helper resolving `OBS-root/config/obs-studio/shader-cache` **from `obs64.exe` itself**. Never silently fall back to the host's ProgramData folder if path resolution fails.
- `plugins/win-capture/plugin-main.c`: skip **only the Game Capture** graphics-hook deployment, hook thread, and Game Capture registration in `obs_module_load`.
- **Keep** `win-capture`, Windows Display Capture, Window Capture, OBS audio sources, desktop audio, microphone recording, and Direct3D renderer.
- Leave OBS's own portable profile behavior and config layout unchanged.
- The packaged launch script uses `--portable --disable-updater`, and `portable_mode.txt` is included.

## Expected layout

```
OBS-Meeting-Portable-TEST/
  LAUNCH-OBS-MEETING-PORTABLE.cmd
  VERIFY-OBS-MEETING-PORTABILITY.cmd
  portable_mode.txt
  bin/64bit/obs64.exe
  data/
  obs-plugins/
  config/obs-studio/basic/scenes/
  config/obs-studio/basic/profiles/
  config/obs-studio/shader-cache/  <-- D3D11 cache here
```

Both `config/obs-studio` user preferences and shader cache stay with this experimental app directory. We do **not** claim that every third-party plugin, GPU driver, browser source, Windows device integration or host OS leaves no traces.

## Build workflow

`.github/workflows/build-obs-meeting-portable.yml` uses a Windows runner matching the current upstream VS 2026 environment and invokes the upstream `Build-Windows.ps1` and `Package-Windows.ps1` scripts. Only the copy of the source checked out **during the action run** is modified.

**Default source is pinned** to the successfully inspected commit `7d98bebe1115b12608837b622164ea5fe6d9483a`. After the first successful build and Windows runtime validation, later upstream branches can be tested separately. Changing source revisions may cause the patch to fail closed.

The build can be large, slow and may be limited by available runner images and GitHub Actions quotas. If the `windows-2025-vs2026` runner is unavailable to your repository, capture the GitHub error rather than swapping in an incompatible image without checking Visual Studio requirements.

## Security and limits

- No Admin prompt, registry modification, or Windows ProgramData deletion is performed by the builder.
- It does not preserve user data between arbitrary manual ZIP replacements: **back up and restore the entire `config` directory** before upgrading the experimental standalone build.
- The existing OBS PAF online installer is **not** modified. Do not feed this experimental ZIP into that online installer yet; it downloads official upstream binaries instead.
- It is too early to disable the hook DLL build targets or remove shared hook DLLs. The patch prevents the OBS Windows capture plugin from calling hook deployment when loading normally. The `frontend/updater` code and third-party integrations remain a **runtime inspection risk**.
- Builds are unsupported binaries; no automatic code signing is included.
- Do not use this to bypass meeting participant consent requirements.

See outer `START-HERE-BEGINNER-GUIDE.txt` and `WINDOWS-TEST-CHECKLIST.txt`.
