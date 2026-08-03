# Medusa v1 backend for hatkari.com — containerized from the ct-1 systemd deployment.
#
# Parity notes (measured from the running system, 2026-08-03):
#   - Node pinned to 20.15.1 = the exact nvm version the shop runs on today.
#   - package.json deps pinned to the exact installed versions from ct-1
#     (`npm ls --depth=0`) because the repo never had a lockfile — a fresh
#     range-resolve could ship different plugin versions than production.
#   - `medusa migrations run` is deliberately NOT part of container start:
#     it runs as an initContainer/Job in k8s so replicas can't race it.
#   - Product images live under /app/uploads (@medusajs/file-local — 2.4G,
#     888 files on ct-1). That path MUST be a PVC in k8s and gets rsynced
#     at cutover; it is .dockerignore'd here.

FROM node:20.15.1-bookworm AS build
WORKDIR /app
# no lockfile exists upstream — hundreds of metadata fetches from shared CI
# runner IPs trip npmjs 429s; retry + throttle instead of failing the build
ENV NPM_CONFIG_FETCH_RETRIES=5 \
    NPM_CONFIG_FETCH_RETRY_MINTIMEOUT=2000 \
    NPM_CONFIG_FETCH_RETRY_MAXTIMEOUT=30000 \
    NPM_CONFIG_MAXSOCKETS=4
COPY package.json npm-shrinkwrap.json ./
# npm ci against the shrinkwrap = the exact 2203-package tree running in
# production (recovered from ct-1's working dir — it was never committed)
RUN npm ci --legacy-peer-deps
COPY . .
# server (tsc) + admin UI; admin build is the memory hog
ENV NODE_OPTIONS=--max-old-space-size=4096
RUN npm run build:server && npm run build:admin

FROM node:20.15.1-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production \
    MEDUSA_EVENT_BUS_TYPE=redis
COPY --from=build /app /app
# runtime uploads mountpoint (PVC in k8s)
RUN mkdir -p /app/uploads
EXPOSE 9000
CMD ["npx", "medusa", "start"]
