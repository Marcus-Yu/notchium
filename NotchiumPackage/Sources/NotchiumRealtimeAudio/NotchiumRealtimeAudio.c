#include "NotchiumRealtimeAudio.h"
#include <string.h>

_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "The audio callback requires lock-free 32-bit atomics");

void NTAudioGainSlotsInitialize(NTAudioGainSlot *slots, uint32_t count) {
    for (uint32_t index = 0; index < count; ++index) {
        atomic_init(&slots[index].gain_bits, 0);
    }
}

void NTAudioGainSlotSet(NTAudioGainSlot *slot, float gain) {
    uint32_t bits = 0;
    memcpy(&bits, &gain, sizeof(bits));
    atomic_store_explicit(&slot->gain_bits, bits, memory_order_release);
}

float NTAudioGainSlotGet(const NTAudioGainSlot *slot) {
    uint32_t bits = atomic_load_explicit(&slot->gain_bits, memory_order_acquire);
    float gain = 0;
    memcpy(&gain, &bits, sizeof(gain));
    return gain;
}

static uint32_t output_frame_count(const AudioBufferList *output, bool noninterleaved) {
    if (!output || output->mNumberBuffers == 0) return 0;
    const AudioBuffer *buffer = &output->mBuffers[0];
    if (!buffer->mData || buffer->mNumberChannels == 0) return 0;
    uint32_t channels = noninterleaved ? 1 : buffer->mNumberChannels;
    return buffer->mDataByteSize / (uint32_t)(sizeof(float) * channels);
}

void NTAudioMixFloat32(
    const AudioBufferList *input,
    AudioBufferList *output,
    const NTAudioGainSlot *slots,
    uint32_t slot_count,
    bool input_noninterleaved,
    bool output_noninterleaved
) {
    if (!input || !output || !slots || slot_count == 0) return;

    const uint32_t frames = output_frame_count(output, output_noninterleaved);
    if (frames == 0) return;

    for (uint32_t buffer_index = 0; buffer_index < output->mNumberBuffers; ++buffer_index) {
        AudioBuffer *buffer = &output->mBuffers[buffer_index];
        if (buffer->mData) memset(buffer->mData, 0, buffer->mDataByteSize);
    }

    const uint32_t buffers_per_slot = input_noninterleaved ? 2 : 1;
    if (input->mNumberBuffers < slot_count * buffers_per_slot) return;

    for (uint32_t slot_index = 0; slot_index < slot_count; ++slot_index) {
        const float gain = NTAudioGainSlotGet(&slots[slot_index]);
        if (gain <= 0.00001f) continue;

        for (uint32_t channel = 0; channel < 2; ++channel) {
            const uint32_t source_index = input_noninterleaved
                ? slot_index * 2 + channel : slot_index;
            const AudioBuffer *source = &input->mBuffers[source_index];
            if (!source->mData || source->mNumberChannels == 0) continue;

            const uint32_t source_channels = input_noninterleaved ? 1 : source->mNumberChannels;
            const uint32_t source_frames = source->mDataByteSize
                / (uint32_t)(sizeof(float) * source_channels);
            const uint32_t count = source_frames < frames ? source_frames : frames;
            const float *source_samples = (const float *)source->mData;

            if (output_noninterleaved) {
                if (channel >= output->mNumberBuffers) continue;
                AudioBuffer *destination = &output->mBuffers[channel];
                if (!destination->mData) continue;
                float *destination_samples = (float *)destination->mData;
                for (uint32_t frame = 0; frame < count; ++frame) {
                    destination_samples[frame] += source_samples[frame * source_channels + channel % source_channels] * gain;
                }
            } else {
                AudioBuffer *destination = &output->mBuffers[0];
                if (!destination->mData || destination->mNumberChannels == 0) continue;
                const uint32_t destination_channels = destination->mNumberChannels;
                if (channel >= destination_channels) continue;
                float *destination_samples = (float *)destination->mData;
                for (uint32_t frame = 0; frame < count; ++frame) {
                    destination_samples[frame * destination_channels + channel]
                        += source_samples[frame * source_channels + channel % source_channels] * gain;
                }
            }
        }
    }

    for (uint32_t buffer_index = 0; buffer_index < output->mNumberBuffers; ++buffer_index) {
        AudioBuffer *buffer = &output->mBuffers[buffer_index];
        if (!buffer->mData) continue;
        const uint32_t sample_count = buffer->mDataByteSize / (uint32_t)sizeof(float);
        float *samples = (float *)buffer->mData;
        for (uint32_t sample = 0; sample < sample_count; ++sample) {
            if (samples[sample] > 1.0f) samples[sample] = 1.0f;
            else if (samples[sample] < -1.0f) samples[sample] = -1.0f;
        }
    }
}
