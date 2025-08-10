FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080

RUN node -e "require('fs').writeFileSync('package.json', JSON.stringify({name:'pdfjs-extractor',version:'1.0.0',type:'commonjs',main:'server.js'}))"
RUN npm i --omit=dev express pdfjs-dist@3 body-parser

RUN cat > server.js <<'EOF'
const express = require('express');
const bodyParser = require('body-parser');

const app = express();
app.use(bodyParser.json({ limit: '25mb' }));

// Always-available health endpoint
app.get('/health', (_req, res) => res.json({ ok: true }));

// Log unexpected errors instead of exiting
process.on('unhandledRejection', err => { console.error('unhandledRejection:', err); });
process.on('uncaughtException', err => { console.error('uncaughtException:', err); });

// Lazy-load pdfjs only on /extract so startup can't fail
app.post('/extract', async (req, res) => {
  try {
    let pdfjsLib;
    try {
      pdfjsLib = require('pdfjs-dist/legacy/build/pdf.js'); // v3 legacy CJS build
    } catch (e) {
      return res.status(500).json({ error: 'pdfjs load failed', detail: String(e) });
    }

    const { getDocument, Util } = pdfjsLib;
    const { url, base64 } = req.body || {};
    if (!url && !base64) return res.status(400).json({ error: 'Provide url or base64' });

    const loadingTask = getDocument(url ? { url } : { data: Buffer.from(base64, 'base64') });
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
        const pageW = viewport.width, pageH = viewport.height;

        items.push({
          str: t.str,
          abs: { x, y: yTop - h, w, h },
          pct: { x: x/pageW*100, y: (yTop-h)/pageH*100, w: w/pageW*100, h: h/pageH*100 }
        });
      }

      pages.push({ pageNumber: p, width: viewport.width, height: viewport.height, items });
    }

    res.json({ numPages: pdf.numPages, pages });
  } catch (e) {
    console.error('extract error:', e);
    res.status(500).json({ error: String(e) });
  }
});

const port = process.env.PORT || 8080;
app.listen(port, () => console.log('pdfjs extractor listening on :' + port));
EOF

RUN adduser -D -H appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8080
CMD ["node", "server.js"]

