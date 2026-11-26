---
name: troubleshoot
description: Diagnose and fix problems with a sunshine-on-demand / Sunshine + Moonlight TV streaming setup - Wake does nothing, PC stays offline, lock screen in the stream, black screen, wrong resolution, controller lag, TV session not starting, Steam window size. Reads status and logs, maps symptoms to fixes.
when_to_use: User reports a problem with streaming to their TV, Moonlight showing the PC offline, Wake-on-LAN not working, or anything misbehaving after installing sunshine-on-demand.
argument-hint: "[what happened]"
---

# sunshine-on-demand troubleshooting

The reference for every symptom is `${CLAUDE_PLUGIN_ROOT}/docs/troubleshooting.md`. Read it first. For how the parts fit together, see `${CLAUDE_PLUGIN_ROOT}/docs/how-it-works.md`.

The installed copy is usually `~/.local/share/sunshine-on-demand` (or wherever the user cloned it): find it with `readlink -f ~/.local/bin/sunshine-on-demand`.

## Steps
1. **Ask what happened and when.** Which step (Wake, boot, stream start, stream end), what the TV and the PC's monitor showed, and roughly the time. Did it happen after a reboot? Then use the previous boot's logs.
2. **Collect:**
   ```bash
   cd "$(dirname "$(dirname "$(readlink -f ~/.local/bin/sunshine-on-demand)")")"
   ./setup.sh status
   ./setup.sh report        # or: ./setup.sh report -1   (previous boot)
   ```
   Read the report file it names. Its timestamps tell the story: wake accepted → TV check / auto-login → TV session locked → stream unlock → display → stream end → relock.
3. **Match the symptom** in `docs/troubleshooting.md` and check that cause specifically. The usual suspects:
   - **Sunshine was updated** → capture fails until `./setup.sh setcap` is re-run.
   - **The client's IP changed** → the Wake listener logs "not the allowed client". Fix it with a DHCP reservation, `CLIENT_IP` in `config.env`, then `install` (user + system).
   - **The TV answers pings in standby** → every boot goes into the TV session. Fix: turn off the TV's network standby, or `TV_AUTOLOGIN="on-wake"`.
   - **Moonlight's Wake gave up after 15 s** → press Retry.
   - **Disconnected without quitting the app** → still unlocked/4K until idle stop. Fix: `sunshine-on-demand stop`.
   - **Stutter / fps drops on a smart TV** → keyframe bursts. Measure with `lgtv-stream-stats start/stop` (LG) and read "Stream quality" in the report. Fix order: decoder NDL (+ start at 40 Mbps on an unknown TV, raise while drops stay ~0; 60 verified on the reference LG) → `SUNSHINE_STRICT_RC` → `STREAM_PACING_MBIT=90` → 1440p → a gigabit box ([stutter](../../docs/troubleshooting.md#stream-stutter-on-smart-tvs)). One change per test session.
   - **Controller ~1 s dropouts** (`failed to send FF report`) → `extras/xbox-controller-bluetooth` (`sudo ./apply.sh`), then a btmon capture if they continue.
   - **Other controller problems** → firmware, antennas, rear USB, pair with the PC.
4. **If the logs don't explain it:**
   - Set `SUNSHINE_LOG_LEVEL="debug"` in `config.env`, run `./setup.sh install --user`, and ask the user to reproduce; then read the report again. The debug log contains every Moonlight request.
   - **Android/Fire TV clients:** `adb logcat | grep -i limelight` shows Moonlight's side.
   - **LG webOS:** Moonlight's own log isn't readable without root; rely on the PC side.
5. **Fix it**, following the setup skill's ground rules: show the change first, use dry-run, and give sudo steps to the user to run in their own terminal. Then **re-test the failing step**.
6. **Turn debug logging back off** afterwards (`SUNSHINE_LOG_LEVEL=""`, then `install --user`).

Never paste or commit the user's IPs, MACs or tokens into the project/plugin folder or any repository.
