# Local config (not tracked by git)

Some settings live **outside** this repo and must be applied per machine. They
are intentionally not versioned:

- **`~/.config/illogical-impulse/config.json`** — Quickshell runtime preferences.
  The bar rewrites this file every time you toggle something in the UI, so
  tracking it would create constant git churn and conflict on upstream pulls.
  The repo only ships the *defaults* in
  `dots/.config/quickshell/ii/modules/common/Config.qml`; this file overrides them.
- **System files under `/etc`** — e.g. pacman hooks. Machine-specific.

This document records the manual steps so a fresh install (or the other machine)
can be brought to the same state.

---

## 1. Quickshell UI preferences

Apply these to `~/.config/illogical-impulse/config.json`. They are safe to run
on any machine using these dotfiles (`jq` creates missing keys, untouched keys
are preserved):

```sh
cd ~/.config/illogical-impulse
cp config.json config.json.bak
jq '
    .dock.pinnedOnStartup = false                          # dock auto-hides, reveals on hover
  | .dock.monochromeIcons = false                          # full-color dock icons
  | .bar.workspaces.monochromeIcons = false                # full-color workspace icons
  | .tray.monochromeIcons = false                          # full-color tray icons
  | .bar.utilButtons.showPerformanceProfileToggle = true   # show power-profile toggle in bar
  | .apps.update = "kitty --hold sh -c '\''sudo pacman -Syu'\''"  # see note below
' config.json > config.json.tmp && mv config.json.tmp config.json
```

Verify:

```sh
jq '{
  pinnedOnStartup: .dock.pinnedOnStartup,
  dock_mono: .dock.monochromeIcons,
  ws_mono: .bar.workspaces.monochromeIcons,
  tray_mono: .tray.monochromeIcons,
  perfToggle: .bar.utilButtons.showPerformanceProfileToggle,
  update: .apps.update
}' config.json
```

Then **restart Quickshell** (not just reload) — `pinnedOnStartup` is only
evaluated at startup. Rollback: `mv config.json.bak config.json`.

---

## 2. Known issues & their fixes

### System update button does nothing after the password prompt

The default update command used `pkexec pacman -Syu`. polkit authentication
hangs/fails in this session context, so after typing the password nothing
happens. Switching to `sudo` is correct, but it must NOT run under an
interactive shell: `fish -i -c 'sudo ...'` floods the terminal with fish's
interactive init (color/OSC escape sequences) that bury sudo's password
prompt, so the window looks blank/gray and never seems to ask. Run it under a
plain `sh -c` (or sudo directly) so the prompt shows cleanly:
`kitty --hold sh -c 'sudo pacman -Syu'`. The repo default in
`dots/.config/quickshell/ii/modules/common/Config.qml` (`apps.update`) is
already set to `sudo`; the `jq` snippet above also overrides it in `config.json`
for existing installs.

### WiFi icon shows "disconnected" while connected (VPN machines)

`Network.qml` treats NetworkManager connectivity `limited` as not-connected and
shows the "bad" icon. With NordVPN (NordLynx), NM's connectivity probe is routed
via fwmark and gets dropped by NordVPN's firewall, so NM reports `limited` even
though the internet works — and the icon looks disconnected.

Fix applied: disable NordVPN's firewall so the probe succeeds and NM reports
`full`:

```sh
nordvpn set firewall disabled
```

> Trade-off: with the firewall off, traffic can leak if the tunnel drops.
> Acceptable here because the Kill Switch is also disabled. Re-enable with
> `nordvpn set firewall enabled` if you turn the Kill Switch back on.

### Password "stops being accepted" without the account being locked

Symptom: sudo/login rejects the correct password; rebooting "fixes" it. The
reboot only helps because time passes — the real cause is two PAM settings:

1. **`pam_faillock`** locks authentication for `unlock_time` (default 600s)
   after `deny` (default 3) failed attempts. A burst of failed auth (e.g. the
   `pkexec`/update issues above) trips it, then every attempt is rejected for
   ~10 minutes even with the right password. No reboot needed — just wait, or
   reset the tally as root:

   ```sh
   faillock --user "$USER"            # inspect failed attempts
   sudo faillock --user "$USER" --reset
   ```

2. **`pam_fprintd` prioritized in sudo** — CachyOS `chwd` adds
   `auth sufficient pam_fprintd.so` as the **first** line of `/etc/pam.d/sudo`.
   With a fingerprint reader present but **no fingerprint enrolled**, every
   sudo first tries the (empty) fingerprint path, causing delays and failed
   attempts that feed faillock. Fix — comment it out so sudo goes straight to
   the password:

   ```sh
   sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.bak
   sudo sd '(?m)^(\s*auth\s+sufficient\s+pam_fprintd\.so.*)$' '#$1' /etc/pam.d/sudo
   sudo faillock --user "$USER" --reset
   # verify in another terminal, keeping a root shell open as a safety net:
   sudo -k; sudo true
   ```

> The line is tagged `# chwd-fprintd`, so CachyOS's `chwd` may re-add it after
> driver/hardware-detection runs. If it comes back, address it at the `chwd`
> level. Alternative fix: actually enroll a fingerprint with `fprintd-enroll`.

---

## 3. Intel iGPU monitoring (Intel machines only)

The GPU widget code (committed in the repo) reads Intel GPU usage via
`intel_gpu_top`, because Intel i915 does **not** expose `gpu_busy_percent` in
sysfs (that file is AMD-only). This needs a tool and a capability.

> AMD machines need **none** of this — the GPU branch is gated on
> `command -v intel_gpu_top`, and AMD is read straight from
> `/sys/class/drm/card*/device/gpu_busy_percent`.

### Install the tool

```sh
sudo pacman -S --needed intel-gpu-tools
```

### Grant the capability

`intel_gpu_top` reads the i915 perf PMU, which is gated by
`perf_event_paranoid`. Grant the narrowest capability (not root, not a
system-wide perf relaxation):

```sh
sudo setcap cap_perfmon+ep /usr/bin/intel_gpu_top
```

### Keep it across package updates

`setcap` is reset whenever `intel-gpu-tools` is upgraded. A pacman hook
reapplies it automatically. Create `/etc/pacman.d/hooks/90-intel-gpu-tools-perfmon.hook`:

```ini
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = intel-gpu-tools

[Action]
Description = Reapplying cap_perfmon to intel_gpu_top (GPU monitoring in bar)...
When = PostTransaction
Exec = /usr/bin/setcap cap_perfmon+ep /usr/bin/intel_gpu_top
```

### Notes

- **GPU temperature** on an Intel iGPU has no dedicated sensor (it shares the
  CPU die). The bar falls back to the `x86_pkg_temp` thermal zone, so the GPU
  temp mirrors the CPU package temp. This is expected, not a bug.
- `fdinfo` (what `nvtop` uses) is **not** a lighter alternative here:
  `kernel.yama.ptrace_scope=1` blocks reading other processes' fdinfo, so it
  would require a system-wide `ptrace_scope=0` — broader than the scoped
  `cap_perfmon` above.
