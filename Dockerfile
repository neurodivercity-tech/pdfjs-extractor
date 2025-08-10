FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080

# Copy only package.json first for better caching
COPY package.json ./
RUN npm install --omit=dev

# Copy the server code
COPY server.js ./server.js

# (optional) run as the non-root 'node' user
USER node

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["node", "server.js"]
