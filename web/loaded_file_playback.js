// Loaded-file playback via Web Audio API (issue #55 — avoids SoLoud buffer underruns).
// Also guards issue #75: intentional stop must not fire the Dart "ended" callback,
// or the next Play can be cancelled by a stale onended/post-frame handler.
(function () {
  let audioContext = null;
  let activeSource = null;
  // Sample rate of the FILE/buffer data (what Dart asked us to play), used for
  // both createBuffer() and the elapsed-time->sample-index math. This must NOT
  // be replaced with audioContext.sampleRate: browsers are free to ignore an
  // unusual requested context sample rate (e.g. clamp/round it to a supported
  // hardware rate), and if that happened while this used audioContext's
  // actual rate, the reported playback position would drift away from real
  // elapsed time by the ratio between the two rates — e.g. a 10000Hz
  // recording played through a context that silently runs at 44100Hz would
  // appear to advance ~4.4x faster than real time, hitting (apparent) EOF in
  // a fraction of the real file duration and leaving the next seek to start
  // near/at EOF with an empty buffer (looks like "can't play after pause").
  let playbackFileSampleRate = 44100;
  let playbackStartCtxTime = 0;
  let playbackStartSample = 0;
  let playbackLengthSamples = 0;
  /** Bumped on every stop/play so stale onended handlers are ignored. */
  let playbackGeneration = 0;
  // Compare against what we last *asked for*, not audioContext.sampleRate —
  // if the browser clamps/ignores our requested rate, comparing to the
  // actual rate would never match and we'd tear down + recreate the context
  // on every single Play() call.
  let lastRequestedContextSampleRate = null;

  function ensureContext(sampleRate) {
    const rate = sampleRate > 0 ? sampleRate : 44100;
    if (!audioContext || lastRequestedContextSampleRate !== rate) {
      lastRequestedContextSampleRate = rate;
      if (audioContext) {
        try {
          audioContext.close();
        } catch (e) {
          console.warn('loadedFilePlayback: close failed', e);
        }
      }
      try {
        audioContext = new (window.AudioContext || window.webkitAudioContext)({
          sampleRate: rate,
        });
      } catch (e) {
        // Requested rate rejected outright (e.g. outside the browser's
        // supported range) — fall back to the default context. Buffer
        // playback below still uses the true file rate, so resampling
        // stays correct even though the context itself runs at its default.
        console.warn('loadedFilePlayback: context create failed for rate', rate, e);
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
      }
      if (audioContext.sampleRate !== rate) {
        console.warn(
          'loadedFilePlayback: browser ignored requested sampleRate',
          rate,
          '-> actual',
          audioContext.sampleRate,
        );
      }
    }
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

  function clearActiveSource({ notifyEnded }) {
    const source = activeSource;
    activeSource = null;
    if (!source) return;
    // Detach first so source.stop() cannot deliver a Dart "ended" for an
    // intentional pause/restart (issue #75 replay-stuck race).
    try {
      source.onended = null;
    } catch (e) {
      /* ignore */
    }
    try {
      source.stop();
    } catch (e) {
      /* already stopped */
    }
    try {
      source.disconnect();
    } catch (e) {
      /* ignore */
    }
    if (notifyEnded && typeof window.dartLoadedFilePlaybackEnded === 'function') {
      window.dartLoadedFilePlaybackEnded();
    }
  }

  window.loadedFilePlaybackStop = function () {
    playbackGeneration++;
    clearActiveSource({ notifyEnded: false });
    playbackStartCtxTime = 0;
    playbackStartSample = 0;
    playbackLengthSamples = 0;
  };

  function startBufferSource(ctx, float32, start, length, generation) {
    // createBuffer's sampleRate need not match ctx.sampleRate — the engine
    // resamples on playback, which is exactly what keeps real-world duration
    // correct when the browser runs the context at a different native rate.
    const buffer = ctx.createBuffer(1, float32.length, playbackFileSampleRate);
    buffer.copyToChannel(float32, 0);

    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(ctx.destination);
    playbackStartCtxTime = ctx.currentTime;
    playbackStartSample = start;
    playbackLengthSamples = length;

    source.onended = function () {
      if (generation !== playbackGeneration) return;
      if (activeSource !== source) return;
      activeSource = null;
      if (typeof window.dartLoadedFilePlaybackEnded === 'function') {
        window.dartLoadedFilePlaybackEnded();
      }
    };

    source.start(0);
    activeSource = source;
  }

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
    playbackFileSampleRate = sampleRate > 0 ? sampleRate : 44100;
    const totalSamples = (pcmBytes.byteLength / 2) | 0;
    const start = Math.max(0, Math.min(startSampleIndex | 0, totalSamples - 1));
    const length = totalSamples - start;
    if (length <= 0) {
      console.warn('loadedFilePlaybackPlay: no samples at offset', start);
      return false;
    }

    const float32 = int16BytesToFloat32(pcmBytes, start, length);
    const generation = ++playbackGeneration;

    const begin = function () {
      if (generation !== playbackGeneration) return;
      try {
        startBufferSource(ctx, float32, start, length, generation);
      } catch (e) {
        console.warn('loadedFilePlaybackPlay: start failed', e);
      }
    };

    // Chrome often starts suspended until a user gesture; resume before start
    // so currentTime advances (otherwise the graph timer sees no progress).
    if (ctx.state === 'suspended') {
      ctx
        .resume()
        .then(begin)
        .catch(function (e) {
          console.warn('loadedFilePlaybackPlay: resume failed', e);
          begin();
        });
    } else {
      begin();
    }
    return true;
  };

  window.loadedFilePlaybackGetSamplePosition = function () {
    if (!audioContext || !activeSource) {
      return playbackStartSample;
    }
    const elapsed = audioContext.currentTime - playbackStartCtxTime;
    const advanced = Math.floor(elapsed * playbackFileSampleRate);
    return Math.min(
      playbackStartSample + advanced,
      playbackStartSample + playbackLengthSamples,
    );
  };

  window.loadedFilePlaybackIsActive = function () {
    return activeSource != null;
  };
})();
