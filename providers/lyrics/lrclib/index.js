// LRCLIB Provider for wisp
// Extracts synchronized and plain lyrics from the LRCLIB open database.

async function getLyrics(query) {
  const artist = query.artist || '';
  const title = query.title || '';
  const album = query.album || '';
  const duration = query.durationSecs || 0;
  const mode = query.mode || 'line';

  console.log('[LRCLIB] getLyrics called: title="' + title + '", artist="' + artist + '", mode=' + mode);

  const params = [
    'artist_name=' + encodeURIComponent(artist),
    'track_name=' + encodeURIComponent(title),
    'album_name=' + encodeURIComponent(album),
    'duration=' + encodeURIComponent(duration)
  ].join('&');

  const url = 'https://lrclib.net/api/get?' + params;
  console.log('[LRCLIB] Requesting: ' + url);
  const res = await wisp.fetch(url, {
    headers: {
      'Accept': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) wisp'
    }
  });

  if (res.status !== 200) {
    console.warn('[LRCLIB] API returned status: ' + res.status);
    return null;
  }
  const data = await res.json();

  const syncedLyrics = (data.syncedLyrics || '').trim();
  const plainLyrics = (data.plainLyrics || '').trim();

  function parseSynced(text) {
    const lines = [];
    const rawLines = text.split('\n');
    const regex = /\[(\d{2}):(\d{2})\.(\d{2,3})\]\s*(.*)/;
    for (let i = 0; i < rawLines.length; i++) {
      const line = rawLines[i].trim();
      if (!line) continue;
      const match = line.match(regex);
      if (match) {
        const min = parseInt(match[1], 10);
        const sec = parseInt(match[2], 10);
        let ms = parseInt(match[3], 10);
        if (match[3].length === 2) ms *= 10;
        lines.push({
          content: match[4] || '',
          startTimeMs: (min * 60 + sec) * 1000 + ms,
          words: []
        });
      } else {
        lines.push({
          content: line,
          startTimeMs: 0,
          words: []
        });
      }
    }
    return lines;
  }

  function parsePlain(text) {
    return text.split('\n').map(l => l.trim()).filter(l => l.length > 0).map(line => ({
      content: line,
      startTimeMs: 0,
      words: []
    }));
  }

  if (mode === 'line' && syncedLyrics) {
    return {
      provider: 'lrclib',
      syncMode: 'line',
      lines: parseSynced(syncedLyrics)
    };
  }

  if (mode === 'unsynced' && plainLyrics) {
    return {
      provider: 'lrclib',
      syncMode: 'unsynced',
      lines: parsePlain(plainLyrics)
    };
  }

  if (syncedLyrics) {
    return {
      provider: 'lrclib',
      syncMode: 'line',
      lines: parseSynced(syncedLyrics)
    };
  }

  if (plainLyrics) {
    return {
      provider: 'lrclib',
      syncMode: 'unsynced',
      lines: parsePlain(plainLyrics)
    };
  }

  return null;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { getLyrics };
}
