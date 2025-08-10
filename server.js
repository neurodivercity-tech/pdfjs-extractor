// Accept raw PDF bytes (no JSON) from n8n "Binary File"
app.post(
  '/extract-binary',
  require('express').raw({ type: ['application/pdf', 'application/octet-stream'], limit: '50mb' }),
  async (req, res) => {
    console.log('extract-binary: request');
    try {
      const pdfjsLib = require('pdfjs-dist/legacy/build/pdf.js'); // lazy-load
      const { getDocument, Util } = pdfjsLib;

      if (!req.body || !req.body.length) {
        return res.status(400).json({ error: 'Empty body' });
      }

      // Convert Buffer -> Uint8Array (what PDF.js expects)
      const buf = Buffer.isBuffer(req.body) ? req.body : Buffer.from(req.body);
      const data = new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);

      const pdf = await getDocument({ data }).promise;

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
            pct: { x: x/W*100, y: (yTop-h)/H*100, w: w/W*100, h: h/H*100 }
          });
        }

        pages.push({ pageNumber: p, width: viewport.width, height: viewport.height, items });
      }

      res.json({ numPages: pdf.numPages, pages });
    } catch (e) {
      console.error('extract-binary error:', e);
      res.status(500).json({ error: String(e) });
    }
  }
);
