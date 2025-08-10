// server.js — stateless PDF text+coords extractor for CapRover

const express = require('express');
const app = express();

// JSON body (for { base64 } or { url })
app.use(express.json({ limit: '50mb' }));

console.log('boot: starting server...');
setInterval(() => console.log('boot: tick'), 10000);

// Always-available health
app.get('/health', (_req, res) => res.json({ ok: true }));

// Shared extractor (no rendering, just text + positions)
async function extractFromPdfUint8(uint8) {
  // Lazy-load legacy CJS build (works great in Node)
  const pdfjsLib = require('pdfjs-dist/legacy/build/pdf.js');
  const { getDocument, Util } = pdfjsLib;

  const pdf = await getDocument({ data: uint8 }).promise;
  const pages = [];

  for (let p = 1; p <= pdf.numPages; p++) {
    const page = await pdf.getPage(p);
    const viewport = page.getViewport({ scale: 1 });
    const textContent = await page.getTextContent();
    const items = [];

    for (const t of textContent.items) {
      // Transform into page coordinate space
      const m = Util.transform(viewport.transform, t.transform);
      const x = m[4], yTop = m[5];
      const h = Math.hypot(m[2], m[3]); // approx text height
      const w = t.width;
      const W = viewport.width, H = viewport.height;

      items.push({
        str: t.str,
        abs: { x, y: yTop - h, w, h }, // top-left box
        pct: { x: x / W * 100, y: (yTop - h) / H * 100, w: w / W * 100, h: h / H * 100 }
      });
    }

    pages.push({ pageNumber: p, width: viewport.width, height: viewport.height, items });
  }

  return { numPages: pages.length, pages };
}

// JSON route: { url } OR { base64 }
app.post('/extract', async (req, res) => {
  console.log('extract: request');
  try {
    const { url, base64 } = req.body || {};
    if (!url && !base64) return res.status(400).json({ error: 'Provide url or base64' });

    if (url) {
      // Let PDF.js fetch it directly
      const pdfjsLib = require('pdfjs-dist/legacy/build/pdf.js');
      const { getDocument, Util } = pdfjsLib;

      const loadingTask = getDocument({ url });
      const pdf = await loadingTask.promise;
      const pages = [];
      for (let p = 1; p <= pdf.numPages; p++) {
        const page = await pdf.getPage(p);
        const viewport = page.getViewport({ scale: 1 });
        const textContent = await page.getTextContent();
        const items = [];
        for (const t of textContent.items) {
          const m = Util.transform(viewport.transform, t.transform);
          const x = m[4], yTop = m[5];
          const h = Math.hypot(m[2], m[3]);
          const w = t.width;
          const W = viewport.width, H = viewport.height;
          items.push({
            str: t.str,
            abs: { x, y: yTop - h, w, h },
            pct: { x: x / W * 100, y: (yTop - h) / H * 100, w: w / W * 100, h: h / H * 100 }
          });
        }
        pages.push({ pageNumber: p, width: viewport.width, height: viewport.height, items });
      }
      return res.json({ numPages: pages.length, pages });
    } else {
      // Handle base64 (with or without data: prefix) -> Uint8Array
      let b64 = String(base64 || '');
      if (b64.startsWith('data:')) {
        const i = b64.indexOf(',');
        if (i !== -1) b64 = b64.slice(i + 1);
      }
      const buf = Buffer.from(b64, 'base64');
      const uint8 = new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
      const result = await extractFromPdfUint8(uint8);
      return res.json(result);
    }
  } catch (e) {
    console.error('extract error:', e);
    res.status(500).json({ error: String(e) });
  }
});

// Binary route: raw PDF bytes (for n8n "Binary File")
app.post(
  '/extract-binary',
  express.raw({ type: ['application/pdf', 'application/octet-stream'], limit: '50mb' }),
  async (req, res) => {
    console.log('extract-binary: request');
    try {
      if (!req.body || !req.body.length) {
        return res.status(400).json({ error: 'Empty body' });
      }
      const buf = Buffer.isBuffer(req.body) ? req.body : Buffer.from(req.body);
      const uint8 = new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
      const result = await extractFromPdfUint8(uint8);
      res.json(result);
    } catch (e) {
      console.error('extract-binary error:', e);
      res.status(500).json({ error: String(e) });
    }
  }
);

const port = process.env.PORT || 8080;
app.listen(port, () => console.log('server: listening on :' + port));
