// BetterLyrics Provider for wisp
// Extracts word-synced and line-synced lyrics using BetterLyrics TTML API.

async function getLyrics(query) {
  const artist = query.artist || '';
  const song = query.title || '';
  const mode = query.mode || 'word';

  console.log('[BetterLyrics] getLyrics called: song="' + song + '", artist="' + artist + '", mode=' + mode);

  const url = 'https://lyrics-api.boidu.dev/getLyrics?artist=' + encodeURIComponent(artist) + '&song=' + encodeURIComponent(song);
  console.log('[BetterLyrics] Requesting: ' + url);
  const res = await wisp.fetch(url, {
    headers: {
      'Accept': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) wisp'
    }
  });

  if (res.status === 401 || res.status !== 200) {
    console.warn('[BetterLyrics] API returned status: ' + res.status);
    return null;
  }
  const data = await res.json();
  const rawTtml = data.ttml;
  if (!rawTtml || typeof rawTtml !== 'string' || !rawTtml.trim()) {
    console.warn('[BetterLyrics] Response JSON had no valid ttml payload');
    return null;
  }

  const ttml = rawTtml.replace(/\\"/g, '"').replace(/\\n/g, '\n').replace(/\\r/g, '\r');

  function parseTimeMs(val) {
    if (!val) return null;
    val = val.trim().toLowerCase();
    if (val.endsWith('ms')) {
      const parsed = parseInt(val.slice(0, -2).trim(), 10);
      return isNaN(parsed) ? null : parsed;
    }
    if (val.endsWith('s')) {
      const parsed = parseFloat(val.slice(0, -1).trim());
      return isNaN(parsed) ? null : Math.round(parsed * 1000);
    }
    const parts = val.split(':');
    if (parts.length === 2 || parts.length === 3) {
      const secStr = parts.pop();
      const minStr = parts.pop();
      const hrStr = parts.length > 0 ? parts.pop() : '0';
      const sec = parseFloat(secStr);
      const min = parseInt(minStr, 10);
      const hr = parseInt(hrStr, 10);
      if (isNaN(sec) || isNaN(min) || isNaN(hr)) return null;
      return Math.round(((hr * 3600) + (min * 60) + sec) * 1000);
    }
    const num = parseFloat(val);
    return isNaN(num) ? null : Math.round(num * 1000);
  }

  function decodeEntities(str) {
    return str
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/&nbsp;/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  const pRegex = /<p\b([^>]*)>([\s\S]*?)<\/p>/gi;
  const attrRegex = /(\w+)="([^"]*)"/g;
  const spanRegex = /<span\b([^>]*)>([\s\S]*?)<\/span>/gi;

  const lines = [];
  let pMatch;

  while ((pMatch = pRegex.exec(ttml)) !== null) {
    const pAttrsStr = pMatch[1];
    const pBody = pMatch[2];

    let pAttrs = {};
    let attrMatch;
    while ((attrMatch = attrRegex.exec(pAttrsStr)) !== null) {
      pAttrs[attrMatch[1].toLowerCase()] = attrMatch[2];
    }

    const startTimeMs = parseTimeMs(pAttrs['begin']) || 0;
    let endTimeMs = parseTimeMs(pAttrs['end']);

    const words = [];
    // Match innermost leaf spans with text content
    const leafSpanRegex = /<span\b([^>]*)>([^<]+)<\/span>/gi;
    let spanMatch;
    while ((spanMatch = leafSpanRegex.exec(pBody)) !== null) {
      const spanAttrsStr = spanMatch[1];
      const spanText = decodeEntities(spanMatch[2]);
      let spanAttrs = {};
      let sAttr;
      while ((sAttr = attrRegex.exec(spanAttrsStr)) !== null) {
        spanAttrs[sAttr[1].toLowerCase()] = sAttr[2];
      }
      if (spanText) {
        const wordStart = parseTimeMs(spanAttrs['begin']) ?? startTimeMs;
        const wordEnd = parseTimeMs(spanAttrs['end']) ?? parseTimeMs(spanAttrs['dur']);
        words.push({
          content: spanText,
          startTimeMs: wordStart,
          endTimeMs: wordEnd
        });
      }
    }

    // Sort words by startTimeMs to prevent out-of-order background vocals from causing timing stutter
    words.sort((a, b) => a.startTimeMs - b.startTimeMs);

    const lineText = decodeEntities(pBody.replace(/<[^>]+>/g, ''));
    if (!lineText) continue;

    if (!endTimeMs && words.length > 0) {
      endTimeMs = words[words.length - 1].endTimeMs;
    }

    lines.push({
      content: lineText,
      startTimeMs: startTimeMs,
      endTimeMs: endTimeMs,
      words: words
    });
  }

  if (lines.length === 0) return null;


  const hasWords = lines.some(l => l.words.length > 0);
  const syncMode = (mode === 'unsynced')
    ? 'unsynced'
    : hasWords
      ? 'word'
      : 'line';

  return {
    version: '1.0',
    provider: 'betterlyrics',
    syncMode: syncMode,
    lines: lines
  };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { getLyrics };
}
