# AflatoonMenu
© AFLATOON | أفلاطون

Single standalone dylib (no Substrate, no jailbreak) for sideloading with ESign.

## Tabs
- **net.c**   : DNS override, now with 6 resolvers (Cloudflare, Google, Quad9, OpenDNS,
                AdGuard, CleanBrowsing) + **net.boost**: TCP_NODELAY, bigger socket
                buffers, low-delay QoS class on this app's own new TCP sockets.
                **Honest limit: this is NOT a VPN.** No tunnel, no encryption, no IP
                change, no traffic re-routing. It cannot fix a bad signal or a slow
                ISP, and changes nothing server-side. It can reduce jitter/stutter on
                an already-working connection, nothing more.
- **voice.m** : YOUR mic pitch (0.5x - 3.0x) through an AudioUnitRender hook (bus 1).
- **room.m**  : speed of EVERYONE ELSE in the room (0.5x - 4.0x), LOCAL PLAYBACK ONLY
                (bus 0). Changes only what you hear on your device; never resent,
                never logged, no effect on other players.
- **eq.c**    : 3-band EQ (bass / mid / treble) on the mic path.
- **info.md** : credits + an honest list of what's hooked and what each limit is.

## DSP engine
Pitch/speed shifting now uses a 3-grain overlap-add (up from 2 grains) for a
smoother result at extreme ratios - same math family as before, just more
overlapping windows so there's less "flutter" when you push the speed hard.

## Build
Push to GitHub -> Actions -> download artifact "AflatoonMenu-dylib".
See the step-by-step guide the assistant gave you for the exact clicks.

## Notes
- room.m depends on the host app pulling its final mixed playback audio through
  AudioUnitRender on bus 0 of the same unit. Common for RemoteIO-based voice/RTC
  SDKs, not guaranteed on every app/SDK version.
- net.boost is local socket tuning only - be straightforward with yourself about
  what it is and isn't before relying on it.
