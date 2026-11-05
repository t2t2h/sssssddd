// Shared.h - AFLATOON
#ifndef AP_SHARED_H
#define AP_SHARED_H

#include <AudioToolbox/AudioToolbox.h>

#define AP_CREDIT_EN  "AFLATOON"
#define AP_CREDIT_AR  "أفلاطون"

// ---- DNS (Hook.m) ----
extern volatile int ap_dnsOn;
extern const char * volatile ap_dnsServer;      // one of the 6 resolver IPs below
void ap_dns_clear_cache(void);

// ---- net.boost (Hook.m) : honest QoS/socket tuning, NOT a VPN ----
extern volatile int ap_netBoostOn;
int ap_net_boosted_count(void);

// ---- Voice (Audio.c) ----
extern volatile int   ap_pitchOn;
extern volatile float ap_pitch;                  // 0.5 .. 2.0
extern volatile int   ap_eqOn;
extern volatile float ap_eqBass, ap_eqMid, ap_eqTreble;   // dB, -12 .. +12

// ---- Room voices (Audio.c) : speed of the OTHER people in the room, locally, on playback ----
extern volatile int   ap_roomOn;
extern volatile float ap_roomSpeed;              // 0.5 .. 3.0 (1.0 = normal)

extern OSStatus (*ap_orig_AudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *,
                                           const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *);
OSStatus ap_AudioUnitRender(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags,
                            const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber,
                            UInt32 inNumberFrames, AudioBufferList *ioData);

// ---- entry points ----
void ap_install_hooks(void);   // Hook.m
void ap_ui_start(void);        // UI.m

#endif
