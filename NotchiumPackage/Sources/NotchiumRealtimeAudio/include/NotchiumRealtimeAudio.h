#ifndef NOTCHIUM_REALTIME_AUDIO_H
#define NOTCHIUM_REALTIME_AUDIO_H

#include <CoreAudio/CoreAudioTypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>

typedef struct {
    _Atomic(uint32_t) gain_bits;
} NTAudioGainSlot;

void NTAudioGainSlotsInitialize(NTAudioGainSlot *slots, uint32_t count);
void NTAudioGainSlotSet(NTAudioGainSlot *slot, float gain);
float NTAudioGainSlotGet(const NTAudioGainSlot *slot);

/// Mixes stereo Float32 tap streams into a Float32 device output buffer.
/// This function is allocation free, lock free, and bounded by frames * slots * 2.
void NTAudioMixFloat32(
    const AudioBufferList *input,
    AudioBufferList *output,
    const NTAudioGainSlot *slots,
    uint32_t slot_count,
    bool input_noninterleaved,
    bool output_noninterleaved
);

#endif
