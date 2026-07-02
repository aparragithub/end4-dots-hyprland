# Voice dictation (whisper.cpp)

Push-to-talk speech-to-text that types the transcript directly into the
focused window (terminal, editor, browser — anything). Works on Wayland /
Hyprland. Runs fully offline and uses the AMD iGPU via Vulkan for inference.

## What is installed

These live **outside** the repo (a system package and a 1.6 GB model), so
they must be reinstalled per machine — they are not versioned here.

| Piece | What | Where |
|-------|------|-------|
| Engine | `whisper.cpp-vulkan` (Arch/CachyOS repo `extra`) | system package |
| Model | `ggml-large-v3-turbo.bin` (~1.6 GB) | `~/.local/share/whisper-models/` |
| Recorder | `pw-record` (PipeWire, already present) | system |
| Typer | `wtype` (Wayland keystroke sim, already present) | system |

### Why these choices

- **Vulkan, not ROCm** — ROCm on the small Phoenix1 iGPU (gfx1103) is flaky
  and usually needs `HSA_OVERRIDE_GFX_VERSION` hacks. Vulkan just works on any
  RDNA3 GPU with no configuration. Confirmed running on `AMD Radeon 780M
  Graphics (RADV PHOENIX)`.
- **large-v3-turbo, not full large-v3** — near-identical accuracy with much
  faster decoding, which matters for a "stop talking → get text" flow. Full
  large-v3 (~3 GB) is slower on an iGPU for no real quality gain here.
- **whisper.cpp, not nerd-dictation/Vosk** — Vosk's Spanish accuracy (even the
  1.4 GB model) was noticeably worse and the big model only ships from a very
  slow server. Whisper is more accurate and the ggml models download fast.

## Tracked in this repo

- `dots/.config/hypr/custom/scripts/dictation-toggle.sh` — the toggle script
- `dots/.config/hypr/custom/keybinds.lua` — binds `SUPER + SHIFT + D`

## How it works

`SUPER + SHIFT + D` toggles a single script:

1. **First press** — starts `pw-record` capturing the mic to
   `/tmp/whisper-dictation.wav` (16 kHz mono, what whisper.cpp expects). A
   notification confirms recording.
2. **Second press** — stops the recorder, runs `whisper-cli` on the clip
   (Spanish, GPU), and pipes the transcript through `wtype` so it is typed
   into whatever window has focus.

State is tracked with a PID file (`/tmp/whisper-dictation.pid`) so one keybind
handles both start and stop.

Unlike a streaming engine, text appears only **after** you stop talking. That
is the trade-off for the much higher accuracy.

## Reinstall on a fresh machine

```sh
# 1. Engine (Vulkan build)
paru -S whisper.cpp-vulkan

# 2. Model (~1.6 GB, from HuggingFace — fast)
mkdir -p ~/.local/share/whisper-models
curl -L -C - -o ~/.local/share/whisper-models/ggml-large-v3-turbo.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
```

The script and keybind come with the dotfiles, so nothing else is needed.

## Verify

```sh
whisper-cli --model ~/.local/share/whisper-models/ggml-large-v3-turbo.bin \
  -l es -nt -f some.wav 2>&1 | grep -i vulkan
```

You should see the Vulkan device line and `using Vulkan0 backend`.

## Tuning

Edit `dots/.config/hypr/custom/scripts/dictation-toggle.sh`:

- `-l es` — spoken language. Use `-l auto` for auto-detect, `-l en`, etc.
- `-t 8` — inference threads. Raise/lower to taste (machine has 16 cores).
- `MODEL` — swap the path to try another ggml model (e.g. a smaller one for
  lower latency, or full `large-v3` for maximum accuracy).
