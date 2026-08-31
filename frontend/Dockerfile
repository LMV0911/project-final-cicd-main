FROM node:20-alpine AS base
WORKDIR /app
COPY package*.json ./

FROM base AS deps
RUN npm ci

FROM deps AS build
COPY . .
RUN npm run build

FROM deps AS development
ENV NODE_ENV=development \
    APP_ENV=development
COPY . .
USER node
EXPOSE 8080
CMD ["npm", "run", "dev"]

FROM base AS runtime
ENV NODE_ENV=production \
    PORT=8080
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
COPY server.cjs ./
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD wget --spider -q http://localhost:8080/health || wget --spider -q http://localhost:8080/ || exit 1

FROM runtime AS staging
ENV APP_ENV=staging \
    NODE_ENV=production
CMD ["node", "server.cjs"]

FROM runtime AS production
ENV APP_ENV=production \
    NODE_ENV=production
CMD ["node", "server.cjs"]
