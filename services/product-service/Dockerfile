FROM node:20-alpine AS base
WORKDIR /app
COPY package*.json ./

FROM base AS deps
RUN npm ci

FROM deps AS build
COPY . .

FROM build AS development
ENV NODE_ENV=development \
    APP_ENV=development
USER node
EXPOSE 3000
CMD ["npm", "run", "dev"]

FROM base AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY . .
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD wget --spider -q http://localhost:3000/api/health || exit 1

FROM runtime AS staging
ENV APP_ENV=staging \
    NODE_ENV=production
CMD ["node", "src/app.js"]

FROM runtime AS production
ENV APP_ENV=production \
    NODE_ENV=production
CMD ["node", "src/app.js"]
