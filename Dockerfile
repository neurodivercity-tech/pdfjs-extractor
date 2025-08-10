FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080

# Install deps
COPY package*.json ./
RUN npm ci --omit=dev

# Copy server
COPY server.js ./server.js

# (optional) run as non-root user that exists in node image
USER node

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["node", "server.js"]
