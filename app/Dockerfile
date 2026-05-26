# syntax=docker/dockerfile:1.7
ARG BUILDER_IMAGE=node:latest
ARG BASE_IMAGE=gcr.io/distroless/nodejs22-debian12

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
