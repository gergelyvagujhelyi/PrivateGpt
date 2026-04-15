# Build context must be the repo root so app/models.yaml is reachable:
#   docker build -f app/admin/Dockerfile -t admin .
FROM node:22-alpine AS build

WORKDIR /app
COPY app/admin/package.json app/admin/package-lock.json* ./
RUN npm ci

COPY app/admin/. .
RUN npm run build

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production \
    MODELS_YAML_PATH=/app/models.yaml

COPY app/admin/package.json app/admin/package-lock.json* ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=build /app/dist ./dist
COPY --from=build /app/shared ./shared
COPY app/models.yaml ./models.yaml

EXPOSE 4000
USER node
CMD ["node", "dist/server/server/index.js"]
