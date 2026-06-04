// Loaded-file playback via Web Audio API (issue #55 — avoids SoLoud buffer underruns).
(function () {
  let audioContext = null;
  let activeSource = null;
  let playbackSampleRate = 44100;
  let playbackStartCtxTime = 0;
  let playbackStartSample = 0;
  let playbackLengthSamples = 0;

  function ensureContext(sampleRate) {
    const rate = sampleRate > 0 ? sampleRate : 44100;
    if (!audioContext || audioContext.sampleRate !== rate) {
      if (audioContext) {
        try {
          audioContext.close();
        } catch (e) {
          console.warn('loadedFilePlayback: close failed', e);
        }
      }
      audioContext = new (window.AudioContext || window.webkitAudioContext)({
        sampleRate: rate,
      });
    }
    if (audioContext.state === 'suspended') {
      audioContext.resume();
    }
    playbackSampleRate = audioContext.sampleRate;
    return audioContext;
  }

  function int16BytesToFloat32(pcmBytes, startSample, numSamples) {
    const view = new DataView(
      pcmBytes.buffer,
      pcmBytes.byteOffset,
      pcmBytes.byteLength,
    );
    const out = new Float32Array(numSamples);
    for (let i = 0; i < numSamples; i++) {
      const s = view.getInt16((startSample + i) * 2, true);
      out[i] = s < 0 ? s / 32768 : s / 32767;
    }
    return out;
  }

  window.loadedFilePlaybackStop = function () {
    if (activeSource) {
      try {
        activeSource.stop();
      } catch (e) {
        /* already stopped */
      }
      try {
        activeSource.disconnect();
      } catch (e) {
        /* ignore */
      }
      activeSource = null;
    }
    playbackStartCtxTime = 0;
    playbackStartSample = 0;
    playbackLengthSamples = 0;
  };

  window.loadedFilePlaybackPlay = function (
    pcmBytes,
    sampleRate,
    startSampleIndex,
  ) {
    window.loadedFilePlaybackStop();
    if (!pcmBytes || pcmBytes.byteLength < 2) {
      console.warn('loadedFilePlaybackPlay: empty PCM');
      return false;
    }

    const ctx = ensureContext(sampleRate);
    const totalSamples = (pcmBytes.byteLength / 2) | 0;
    const start = Math.max(0, Math.min(startSampleIndex | 0, totalSamples - 1));
    const length = totalSamples - start;
    if (length <= 0) {
      console.warn('loadedFilePlaybackPlay: no samples at offset', start);
      return false;
    }

    const float32 = int16BytesToFloat32(pcmBytes, start, length);
    const buffer = ctx.createBuffer(1, float32.length, playbackSampleRate);
    buffer.copyToChannel(float32, 0);

    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(ctx.destination);
    playbackStartCtxTime = ctx.currentTime;
    playbackStartSample = start;
    playbackLengthSamples = length;

    source.onended = function () {
      activeSource = null;
      if (typeof window.dartLoadedFilePlaybackEnded === 'function') {
        window.dartLoadedFilePlaybackEnded();
      }
    };

    source.start(0);
    activeSource = source;
    return true;
  };

  window.loadedFilePlaybackGetSamplePosition = function () {
    if (!audioContext || !activeSource) {
      return playbackStartSample;
    }
    const elapsed = audioContext.currentTime - playbackStartCtxTime;
    const advanced = Math.floor(elapsed * playbackSampleRate);
    return Math.min(playbackStartSample + advanced, playbackStartSample + playbackLengthSamples);
  };

  window.loadedFilePlaybackIsActive = function () {
    return activeSource != null;
  };
})();
