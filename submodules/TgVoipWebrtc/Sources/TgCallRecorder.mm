#import "TgCallRecorder.h"
#import <Foundation/Foundation.h>
#include <mutex>
#include <cstdio>
#include <cstring>
#include <vector>
#include <algorithm>

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
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            id enabledObj = [defaults objectForKey:@"tg_mod_call_recorder_enabled"];
            if (enabledObj != nil && ![defaults boolForKey:@"tg_mod_call_recorder_enabled"]) {
                return;
            }

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

            _currentFilePath = filePath;
            _sampleRate = sampleRate > 0 ? sampleRate : 48000;
            _channels = 1; // Always mix to mono
            _totalBytesWritten = 0;
            _micBuffer.clear();
            _speakerBuffer.clear();

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

    void writeMicSamples(const void *samples, size_t nSamples, size_t nBytesPerSample, size_t nChannels, uint32_t /*sampleRate*/) {
        if (!samples || nSamples == 0) {
            return;
        }

        std::lock_guard<std::mutex> lock(_mutex);
        if (!_file) {
            return;
        }

        appendSamples(_micBuffer, samples, nSamples, nBytesPerSample, nChannels);
        mixBuffers();
    }

    void writeSpeakerSamples(const void *samples, size_t nSamples, size_t nBytesPerSample, size_t nChannels, uint32_t /*sampleRate*/) {
        if (!samples || nSamples == 0) {
            return;
        }

        std::lock_guard<std::mutex> lock(_mutex);
        if (!_file) {
            return;
        }

        appendSamples(_speakerBuffer, samples, nSamples, nBytesPerSample, nChannels);
        mixBuffers();
    }

    void stop() {
        std::lock_guard<std::mutex> lock(_mutex);
        stopInternal();
    }

    NSString *getLastRecordingPath() {
        std::lock_guard<std::mutex> lock(_mutex);
        return _lastRecordingPath;
    }

private:
    CallRecorderImpl() : _file(nullptr), _sampleRate(48000), _channels(1), _totalBytesWritten(0), _currentFilePath(nil), _lastRecordingPath(nil) {}
    ~CallRecorderImpl() {
        stopInternal();
    }

    void appendSamples(std::vector<int16_t> &buffer, const void *samples, size_t nSamples, size_t nBytesPerSample, size_t nChannels) {
        if (nBytesPerSample != sizeof(int16_t)) {
            return;
        }
        const int16_t *src = static_cast<const int16_t *>(samples);
        if (nChannels == 1) {
            buffer.insert(buffer.end(), src, src + nSamples);
        } else if (nChannels == 2) {
            buffer.reserve(buffer.size() + nSamples);
            for (size_t i = 0; i < nSamples; i++) {
                int32_t sum = static_cast<int32_t>(src[i * 2]) + static_cast<int32_t>(src[i * 2 + 1]);
                buffer.push_back(static_cast<int16_t>(sum / 2));
            }
        }
    }

    void mixBuffers() {
        if (!_file) {
            return;
        }

        size_t mixCount = std::min(_micBuffer.size(), _speakerBuffer.size());
        if (mixCount > 0) {
            std::vector<int16_t> out(mixCount);
            for (size_t i = 0; i < mixCount; i++) {
                int32_t sum = static_cast<int32_t>(_micBuffer[i]) + static_cast<int32_t>(_speakerBuffer[i]);
                if (sum > 32767) sum = 32767;
                else if (sum < -32768) sum = -32768;
                out[i] = static_cast<int16_t>(sum);
            }
            fwrite(out.data(), sizeof(int16_t), mixCount, _file);
            _totalBytesWritten += static_cast<uint32_t>(mixCount * sizeof(int16_t));
            _micBuffer.erase(_micBuffer.begin(), _micBuffer.begin() + mixCount);
            _speakerBuffer.erase(_speakerBuffer.begin(), _speakerBuffer.begin() + mixCount);
        }

        // Prevent buffer drift if one side is silent/inactive
        const size_t kMaxBuffer = 48000; // 1 second of 48kHz audio
        if (_micBuffer.size() > kMaxBuffer) {
            size_t excess = _micBuffer.size() - kMaxBuffer;
            fwrite(_micBuffer.data(), sizeof(int16_t), excess, _file);
            _totalBytesWritten += static_cast<uint32_t>(excess * sizeof(int16_t));
            _micBuffer.erase(_micBuffer.begin(), _micBuffer.begin() + excess);
        }
        if (_speakerBuffer.size() > kMaxBuffer) {
            size_t excess = _speakerBuffer.size() - kMaxBuffer;
            fwrite(_speakerBuffer.data(), sizeof(int16_t), excess, _file);
            _totalBytesWritten += static_cast<uint32_t>(excess * sizeof(int16_t));
            _speakerBuffer.erase(_speakerBuffer.begin(), _speakerBuffer.begin() + excess);
        }
    }

    void stopInternal() {
        if (_file) {
            // Drain remaining samples
            if (!_micBuffer.empty()) {
                fwrite(_micBuffer.data(), sizeof(int16_t), _micBuffer.size(), _file);
                _totalBytesWritten += static_cast<uint32_t>(_micBuffer.size() * sizeof(int16_t));
                _micBuffer.clear();
            }
            if (!_speakerBuffer.empty()) {
                fwrite(_speakerBuffer.data(), sizeof(int16_t), _speakerBuffer.size(), _file);
                _totalBytesWritten += static_cast<uint32_t>(_speakerBuffer.size() * sizeof(int16_t));
                _speakerBuffer.clear();
            }

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

            _lastRecordingPath = _currentFilePath;
            _currentFilePath = nil;
            _totalBytesWritten = 0;
        }
    }

    std::mutex _mutex;
    FILE *_file;
    uint32_t _sampleRate;
    uint16_t _channels;
    uint32_t _totalBytesWritten;
    NSString *_currentFilePath;
    NSString *_lastRecordingPath;
    std::vector<int16_t> _micBuffer;
    std::vector<int16_t> _speakerBuffer;
};

} // namespace

void TgCallRecorderStart(uint32_t sampleRate, uint16_t channels) {
    CallRecorderImpl::shared().start(sampleRate, channels);
}

void TgCallRecorderWriteMicSamples(const void *audioSamples, size_t nSamples, size_t nBytesPerSample, size_t nChannels, uint32_t sampleRate) {
    CallRecorderImpl::shared().writeMicSamples(audioSamples, nSamples, nBytesPerSample, nChannels, sampleRate);
}

void TgCallRecorderWriteSpeakerSamples(const void *audioSamples, size_t nSamples, size_t nBytesPerSample, size_t nChannels, uint32_t sampleRate) {
    CallRecorderImpl::shared().writeSpeakerSamples(audioSamples, nSamples, nBytesPerSample, nChannels, sampleRate);
}

void TgCallRecorderWriteSamples(const void *audioSamples, size_t nSamples, size_t nBytesPerSample, size_t nChannels, uint32_t sampleRate) {
    CallRecorderImpl::shared().writeMicSamples(audioSamples, nSamples, nBytesPerSample, nChannels, sampleRate);
}

void TgCallRecorderStop(void) {
    CallRecorderImpl::shared().stop();
}

NSString *TgCallRecorderGetLastRecordingPath(void) {
    return CallRecorderImpl::shared().getLastRecordingPath();
}
