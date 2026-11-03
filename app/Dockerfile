# Build stage
FROM node:20-alpine3.20 AS dependencies
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force

# Production stage
FROM node:20-alpine3.20 AS runner
ENV NODE_ENV=production \
    PORT=8080

WORKDIR /usr/src/app

# Update OS packages and remove apk cache
RUN apk update && apk upgrade --no-cache && rm -rf /var/cache/apk/* /tmp/*

COPY --chown=node:node --from=dependencies /app/node_modules ./node_modules
COPY --chown=node:node package*.json ./
COPY --chown=node:node src/ ./src/

USER node
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:8080/healthz', (r) => { if (r.statusCode !== 200) process.exit(1); });"

CMD ["node", "src/app.js"]
