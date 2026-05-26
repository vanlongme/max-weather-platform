# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=cgr.dev/chainguard/node:latest-dev
ARG BUILDER_IMAGE=cgr.dev/chainguard/node:latest-dev

FROM ${BUILDER_IMAGE} AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

FROM ${BASE_IMAGE} AS runtime
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY src ./src
COPY package.json ./
USER 65532
EXPOSE 8080
CMD ["src/server.js"]
