// Audio.c - AudioUnitRender hook - AFLATOON
//   bus 1 (mic input)        -> pitch + EQ   (ap_pitchOn / ap_eqOn)
//   bus 0 (room / playback)  -> speed only   (ap_roomOn)   <- the OTHER people in the room, local playback only
#include "Shared.h"
#include "DSP.h"
#include <string.h>

volatile int   ap_pitchOn = 0;
volatile float ap_pitch = 1.0f;
volatile int   ap_eqOn = 0;
volatile float ap_eqBass = 0.0f, ap_eqMid = 0.0f, ap_eqTreble = 0.0f;

volatile int   ap_roomOn = 0;
volatile float ap_roomSpeed = 1.0f;

OSStatus (*ap_orig_AudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *,
                                    const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *) = 0;

// one slot per (AudioUnit, bus) pair - mic and room state never mix, even on the same unit
#define AP_SLOTS 6
typedef struct {
    AudioUnit unit;
    UInt32    bus;
    int       used;
    int       supported;
    int       isFloat;
    AP_Voice  v;
} Slot;
static Slot gSlots[AP_SLOTS];

static Slot *slot_for(AudioUnit u, UInt32 bus, UInt32 bytesPerSample) {
    for (int i = 0; i < AP_SLOTS; i++)
        if (gSlots[i].used && gSlots[i].unit == u && gSlots[i].bus == bus) return &gSlots[i];
    for (int i = 0; i < AP_SLOTS; i++) {
        if (gSlots[i].used) continue;
        double fs = 48000.0;
        int supported = (bytesPerSample == 2 || bytesPerSample == 4);
        int isFloat = (bytesPerSample == 4);
        AudioStreamBasicDescription d;
        UInt32 sz = sizeof d;
        memset(&d, 0, sizeof d);
        // the buffer AudioUnitRender fills for a given bus always carries that bus's Output-scope format
        if (AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, bus, &d, &sz) == noErr) {
            if (d.mSampleRate > 0) fs = d.mSampleRate;
            if (d.mFormatID == kAudioFormatLinearPCM) {
                if ((d.mFormatFlags & kAudioFormatFlagIsFloat) && d.mBitsPerChannel == 32) { supported = 1; isFloat = 1; }
                else if (!(d.mFormatFlags & kAudioFormatFlagIsFloat) && (d.mFormatFlags & kAudioFormatFlagIsSignedInteger) && d.mBitsPerChannel == 16) { supported = 1; isFloat = 0; }
                else supported = 0;
            } else supported = 0;
        }
        ap_voice_init(&gSlots[i].v, fs);
        gSlots[i].supported = supported;
        gSlots[i].isFloat = isFloat;
        gSlots[i].bus = bus;
        gSlots[i].unit = u;
        gSlots[i].used = 1;     // publish last
        return &gSlots[i];
    }
    return NULL;
}

// shared plumbing: validate the buffer, find/alloc its slot, run the DSP
static void process_bus(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags,
                        UInt32 inNumberFrames, AudioBufferList *ioData, UInt32 bus,
                        int pitchOn, float pitch, int eqOn, float bassDB, float midDB, float trebleDB) {
    if (!pitchOn && !eqOn) return;
    if (ioActionFlags && (*ioActionFlags & kAudioUnitRenderAction_OutputIsSilence)) return;

    UInt32 nb = ioData->mNumberBuffers;
    if (nb < 1 || nb > 2) return;
    int interleaved = (nb == 1);
    int ch = interleaved ? (int)ioData->mBuffers[0].mNumberChannels : (int)nb;
    if (ch < 1 || ch > 2) return;
    if (!ioData->mBuffers[0].mData) return;
    if (!interleaved && !ioData->mBuffers[1].mData) return;

    UInt32 bytes = ioData->mBuffers[0].mDataByteSize;
    UInt32 div = inNumberFrames * (interleaved ? (UInt32)ch : 1u);
    if (div == 0 || bytes % div != 0) return;
    UInt32 bps = bytes / div;
    if (bps != 2 && bps != 4) return;

    Slot *s = slot_for(inUnit, bus, bps);
    if (!s || !s->supported) return;
    if ((s->isFloat && bps != 4) || (!s->isFloat && bps != 2)) return;

    void *bufs[2] = { ioData->mBuffers[0].mData, nb > 1 ? ioData->mBuffers[1].mData : NULL };
    ap_voice_process(&s->v, bufs, ch, interleaved, s->isFloat, (int)inNumberFrames,
                     pitchOn, pitch, eqOn, bassDB, midDB, trebleDB);
}

OSStatus ap_AudioUnitRender(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags,
                            const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber,
                            UInt32 inNumberFrames, AudioBufferList *ioData) {
    OSStatus st = ap_orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp,
                                          inOutputBusNumber, inNumberFrames, ioData);
    if (st != noErr || !ioData || inNumberFrames == 0) return st;

    if (inOutputBusNumber == 1) {
        // mic input: pitch + EQ, exactly as before
        process_bus(inUnit, ioActionFlags, inNumberFrames, ioData, 1,
                   ap_pitchOn, ap_pitch, ap_eqOn, ap_eqBass, ap_eqMid, ap_eqTreble);
    } else if (inOutputBusNumber == 0) {
        // room / playback bus: the mixed voices of everyone else, speed only, local ears only
        process_bus(inUnit, ioActionFlags, inNumberFrames, ioData, 0,
                   ap_roomOn, ap_roomSpeed, 0, 0, 0, 0);
    }
    return st;
}
