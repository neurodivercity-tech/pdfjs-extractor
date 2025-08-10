# Stateless PDF.js extractor (internal-only service)
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080

# Create minimal package.json inside the image
RUN node -e "require('fs').writeFileSync('package.json', JSON.stringify({name:'pdfjs-extractor',version:'1.0.0',type:'commonjs',main:'server.js'}))"

# Install deps
RUN npm i --omit=dev express pdfjs-dist body-parser

# Generate server.js inside the image
RUN cat > server.js <<'EOF'
const express = require('express');
const bodyParser = require('body-parser');
const pdfjsLib = require('pdfjs-dist');
const app = express();
app.use(bodyParser.json({ limit: '25mb' }));

// PDF.js worker for Node
pdfjsLib.GlobalWorkerOptions.workerSrc = require('pdfjs-dist/build/pdf.worker.js');
const { getDocument, Util } = pdfjsLib;

// Health
app.get('/health', (_req, res) => res.json({ ok: true }));

// POST /extract { url } or { base64 }
app.post('/extract', async (req, res) => {
  try {
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
        const x = m[4];
        const yTop = m[5];
        const h = Math.hypot(m[2], m[3]);
        const w = t.width;
        const pageW = viewport.width;
        const pageH = viewport.height;

        items.push({
          str: t.str,
          abs: { x, y: yTop - h, w, h },
          pct: { x: (x / pageW) * 100, y: ((yTop - h) / pageH) * 100, w: (w / pageW) * 100, h: (h / pageH) * 100 }
        });
      }

      pages.push({ pageNumber: p, width: viewport.width, height: viewport.height, items });
    }

    res.json({ numPages: pdf.numPages, pages });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

const port = process.env.PORT || 8080;
app.listen(port, () => console.log('pdfjs extractor listening on :' + port));
EOF

# Run as non-root
RUN adduser -D -H appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8080
CMD ["node", "server.js"]
