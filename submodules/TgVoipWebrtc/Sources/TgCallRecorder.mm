#import "TgCallRecorder.h"
#import <Foundation/Foundation.h>
#include <mutex>
#include <cstdio>
#include <cstring>
#include <ctime>

namespace {

struct WavHeader {
    char riffHeader[4] = {'R', 'I', 'F', 'F'};
    uint32_t riffSize = 0;
    char waveHeader[4] = {'W', 'A', 'V', 'E'};
    char fmtHeader[4] = {'f', 'm', 't', ' '};
    uint32_t fmtSize = 16;
    uint16_t audioFormat = 1; // PCM
    uint16_t numChannels = 1;
    uint32_t sampleRate = 48000;
    uint32_t byteRate = 96000;
    uint16_t blockAlign = 2;
    uint16_t bitsPerSample = 16;
    char dataHeader[4] = {'d', 'a', 't', 'a'};
    uint32_t dataSize = 0;
};

class CallRecorderImpl {
public:
    static CallRecorderImpl &shared() {
        static CallRecorderImpl instance;
        return instance;
    }

    void start(uint32_t sampleRate, uint16_t channels) {
        std::lock_guard<std::mutex> lock(_mutex);
        if (_file) {
            stopInternal();
        }

        @autoreleasepool {
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsDirectory = [paths firstObject];
            if (!documentsDirectory) {
                return;
            }

            NSString *recordingsDir = [documentsDirectory stringByAppendingPathComponent:@"CallRecordings"];
            NSFileManager *fm = [NSFileManager defaultManager];
            if (![fm fileExistsAtPath:recordingsDir]) {
                [fm createDirectoryAtPath:recordingsDir withIntermediateDirectories:YES attributes:nil error:nil];
            }

            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"yyyy-MM-dd_HH-mm-ss";
            NSString *timestamp = [formatter stringFromDate:[NSDate date]];
            NSString *filePath = [recordingsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"Call_%@.wav", timestamp]];

            _file = fopen([filePath UTF8String], "wb");
            if (!_file) {
                return;
            }

            _sampleRate = sampleRate > 0 ? sampleRate : 48000;
            _channels = channels > 0 ? channels : 1;
            _totalBytesWritten = 0;

            WavHeader header;
            header.numChannels = _channels;
            header.sampleRate = _sampleRate;
            header.bitsPerSample = 16;
            header.blockAlign = _channels * sizeof(int16_t);
            header.byteRate = _sampleRate * header.blockAlign;
            header.riffSize = 36;
            header.dataSize = 0;

            fwrite(&header, sizeof(WavHeader), 1, _file);
            fflush(_file);
        }
    }

    void write(const void *samples, size_t nSamples, size_t nBytesPerSample, size_t nChannels, uint32_t sampleRate) {
        if (!samples || nSamples == 0) {
            return;
        }

        std::lock_guard<std::mutex> lock(_mutex);
        if (!_file) {
            return;
        }

        size_t byteCount = nSamples * nBytesPerSample * nChannels;
        size_t written = fwrite(samples, 1, byteCount, _file);
        _totalBytesWritten += (uint32_t)written;
    }

    void stop() {
        std::lock_guard<std::mutex> lock(_mutex);
        stopInternal();
    }

private:
    CallRecorderImpl() : _file(nullptr), _sampleRate(48000), _channels(1), _totalBytesWritten(0) {}
    ~CallRecorderImpl() {
        stopInternal();
    }

    void stopInternal() {
        if (_file) {
            fseek(_file, 0, SEEK_SET);

            WavHeader header;
            header.numChannels = _channels;
            header.sampleRate = _sampleRate;
            header.bitsPerSample = 16;
            header.blockAlign = _channels * sizeof(int16_t);
            header.byteRate = _sampleRate * header.blockAlign;
            header.riffSize = 36 + _totalBytesWritten;
            header.dataSize = _totalBytesWritten;

            fwrite(&header, sizeof(WavHeader), 1, _file);
            fflush(_file);
            fclose(_file);
            _file = nullptr;
            _totalBytesWritten = 0;
        }
    }

    std::mutex _mutex;
    FILE *_file;
    uint32_t _sampleRate;
    uint16_t _channels;
    uint32_t _totalBytesWritten;
};

} // namespace

void TgCallRecorderStart(uint32_t sampleRate, uint16_t channels) {
    CallRecorderImpl::shared().start(sampleRate, channels);
}

void TgCallRecorderWriteSamples(const void *audioSamples, size_t nSamples, size_t nBytesPerSample, size_t nChannels, uint32_t sampleRate) {
    CallRecorderImpl::shared().write(audioSamples, nSamples, nBytesPerSample, nChannels, sampleRate);
}

void TgCallRecorderStop(void) {
    CallRecorderImpl::shared().stop();
}
