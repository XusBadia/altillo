# Director cut · audio

## Master

`public/audio/director-score.wav` is a **40.000000 s**, 48 kHz, stereo, 24-bit PCM master (1,920,000 samples per channel). Place it once at frame 0, at volume 1, for a 1,200-frame / 30 fps composition. Mute all existing footage audio and the previous demo bed; do not apply the Music module's play/pause state to this soundtrack.

The previous film used three different clip soundtracks, a repeated ambience in the demo, and no soundtrack over its four-second signature. This master replaces those disconnected sections with one continuous musical source.

## Source and edit

The source is a new native Grok Imagine generation, saved alongside the master as `director-music-source.mp4`. It used the existing door still solely as the required video-generation input; none of that new video's imagery is intended for the film. No external artist's track, Apple audio, paid subscription, or API credential was used.

Generation direction: an acoustic instrumental loop with felt piano, ascending motif, pizzicato responses, brushed pulse and acoustic bass; no voice or sound effects. The requested tempo/key are creative direction, not independently verified musical properties.

The source spectrogram shows sustained harmonic notes and regular transient attacks throughout, rather than the earlier nearly silent ambience. Its integrated level is −13.11 LUFS; the earlier attic audio was −39.46 LUFS.

Editing:

- Four 10.75-second pitch-preserving phrases, joined with three one-second equal-power crossfades, produce exactly 40 seconds.
- Low-cut at 45 Hz and high-cut at 14.5 kHz; no artificial stereo widening.
- Opening gain rises gently across seven seconds; closing passage reduces by only 10%, retaining music under the signature.
- 120 ms opening fade and 700 ms end fade, beginning at 39.3 seconds. No intermediate mute or fade-to-silence.
- Two-pass loudness normalization, followed by an exact sample-length trim.

## Measured QA

| Check | Result |
|---|---|
| Duration | 40.000000 s |
| Sample count per channel | 1,920,000 |
| Integrated loudness | −18.00 LUFS |
| True peak | −6.14 dBTP |
| Loudness range | 1.70 LU |
| Final 36–40 s RMS level | −20.8 dBFS |
| Final 36–40 s peak | −6.7 dBFS |
| Silence detection | No interval ≥150 ms below −45 dBFS |

The last check includes the full ending. Final encoded video must be checked again, since composition-level volume changes can invalidate these measurements.

Limit: no tool with genuine audio-listening input was available to this editor. Waveform/spectrum, loudness, duration, clipping headroom and silence were verified; this document does **not** claim a human-style listening audition or prove the subjective quality of the generated instrumentation.

## Final encoded film gate

Checked the completed `videos/altillo-director-cut.mp4` after its renderer exited successfully, not a growing file. **Technical audio gate: pass.**

| Check | Encoded result |
|---|---|
| Picture duration | 40.000000 s / 1,200 frames |
| AAC stream/container duration | 40.064000 s, including encoder padding |
| Audio format | AAC, 48 kHz, stereo, approximately 253 kb/s |
| Integrated loudness | −18.04 LUFS |
| True peak | −6.14 dBTP |
| Loudness range | 1.70 LU |
| Final 36–40 s RMS / peak | −20.8 / −6.8 dBFS |
| Silence through picture duration | No interval ≥150 ms below −45 dBFS |
| Decoding | Entire audio stream decoded without errors |

The final second retains music and tapers down into the ending; there is no four-second silent signature. Comparing the clean opening against the PCM master gives 0.9985 waveform correlation and 0.9964 relative gain after compensating for approximately 42.7 ms of encoding offset. This supports that the intended master survived export at essentially unity gain. Quiet intentional paper/contact foley remains in the demo; this comparison does not misclassify it as accidental duplicate music.

The additional 64 ms of AAC duration is encoder padding, not extra picture or a missing musical ending. The subjective-listening limitation stated above still applies.
