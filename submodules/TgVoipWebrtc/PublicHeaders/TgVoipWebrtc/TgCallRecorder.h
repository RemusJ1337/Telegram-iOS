#ifndef TG_CALL_RECORDER_H
#define TG_CALL_RECORDER_H

#import <Foundation/Foundation.h>
#include <cstdint>
#include <cstddef>

#ifdef __cplusplus
extern "C" {
#endif

void TgCallRecorderStart(uint32_t sampleRate, uint16_t channels);
void TgCallRecorderWriteMicSamples(const void * _Nonnull audioSamples, size_t nSamples, size_t nBytesPerSample, size_t nChannels, uint32_t sampleRate);
void TgCallRecorderWriteSpeakerSamples(const void * _Nonnull audioSamples, size_t nSamples, size_t nBytesPerSample, size_t nChannels, uint32_t sampleRate);
void TgCallRecorderWriteSamples(const void * _Nonnull audioSamples, size_t nSamples, size_t nBytesPerSample, size_t nChannels, uint32_t sampleRate);
void TgCallRecorderStop(void);
NSString * _Nullable TgCallRecorderGetLastRecordingPath(void);

#ifdef __cplusplus
}
#endif

#endif // TG_CALL_RECORDER_H
