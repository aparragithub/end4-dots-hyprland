#!/usr/bin/env bash
# Toggle push-to-talk voice dictation with whisper.cpp (Vulkan on AMD iGPU).
#
# Flow: first keypress starts recording the mic to a temp WAV via pw-record
# (PipeWire); second keypress stops the recorder, runs whisper-cli on the
# clip, and types the transcript into the focused window with wtype. Unlike
# streaming engines, text appears only after you stop talking — the trade-off
# for large-v3-turbo's much higher accuracy. State is tracked via a PID file
# so one keybind toggles both directions.
set -euo pipefail

MODEL="$HOME/.local/share/whisper-models/ggml-large-v3-turbo.bin"
WAV="/tmp/whisper-dictation.wav"
PIDFILE="/tmp/whisper-dictation.pid"

notify() { notify-send "Dictation" "$1" -t "${2:-1500}" -a whisper 2>/dev/null || true; }

# Already recording -> stop, transcribe, type.
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
    notify "Transcribing..." 2000

    # whisper-cli needs the model; -nt drops timestamps, -np silences logs so
    # stdout is just the transcript. Threads capped to keep the desktop snappy.
    text="$(whisper-cli --model "$MODEL" -l es -nt -np -t 8 -f "$WAV" 2>/dev/null \
        | tr '\n' ' ' | sed 's/^ *//; s/ *$//')"

    if [[ -n "$text" ]]; then
        wtype "$text"
        notify "Done" 1000
    else
        notify "No speech detected" 1500
    fi
    rm -f "$WAV"
else
    # Not recording -> start. 16 kHz mono s16 is what whisper.cpp expects.
    notify "Recording... (press again to stop)" 1000
    pw-record --rate 16000 --channels 1 --format s16 "$WAV" &
    echo $! > "$PIDFILE"
fi
