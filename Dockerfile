FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080

RUN node -e "require('fs').writeFileSync('package.json', JSON.stringify({name:'pdfjs-extractor',version:'1.0.0',type:'commonjs',main:'server.js'}))"
RUN npm i --omit=dev express pdfjs-dist@3

RUN cat > server.js <<'EOF'
const express = require('express');
const app = express();
app.use(express.json({ limit: '25mb' }));

console.log('boot: starting server...');
setInterval(() => console.log('boot: tick'), 10000);

app.get('/health', (_req, res) => res.json({ ok: true }));

process.on('unhandledRejection', e => console.error('unhandledRejection:', e));
process.on('uncaughtException',  e => console.error('uncaughtException:',  e));

app.post('/extract', async (req, res) => {
  console.log('extract: request');
  try {
    let pdfjsLib;
    try { pdfjsLib = require('pdfjs-dist/legacy/build/pdf.js'); }
    catch (e) { console.error('pdfjs load failed:', e); return res.status(500).json({ error: 'pdfjs load failed', detail: String(e) }); }

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
        const W = viewport.width, H = viewport.height;

        items.push({ str: t.str, abs: { x, y: yTop - h, w, h }, pct: { x: x/W*100, y: (yTop-h)/H*100, w: w/W*100, h: h/H*100 } });
      }
      pages.push({ pageNumber: p, width: viewport.width, height: viewport.height, items });
    }

    console.log('extract: done pages=', pages.length);
    res.json({ numPages: pdf.numPages, pages });
  } catch (e) {
    console.error('extract error:', e);
    res.status(500).json({ error: String(e) });
  }
});

const port = process.env.PORT || 8080;
app.listen(port, () => console.log('server: listening on :' + port));
EOF

EXPOSE 8080
CMD ["node", "server.js"]
