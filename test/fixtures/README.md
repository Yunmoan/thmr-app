Synthetic MP3 test tones generated for this repository; no third-party recordings.
The runtime tests consume these files directly and do not require FFmpeg.

Regeneration (development only):

```sh
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi \
  -i sine=frequency=1000:sample_rate=44100:duration=2 -ac 2 \
  -codec:a libmp3lame -b:a 128k -write_xing 0 -map_metadata -1 \
  -y test/fixtures/sine_1000hz_44100_stereo.mp3
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi \
  -i sine=frequency=440:sample_rate=48000:duration=2 -ac 1 \
  -codec:a libmp3lame -b:a 96k -write_xing 0 -map_metadata -1 \
  -y test/fixtures/sine_440hz_48000_mono.mp3
```
