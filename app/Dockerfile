# Use a small Node LTS base
FROM node:20-alpine AS builder
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm ci --only=production
COPY . .


FROM node:20-alpine
WORKDIR /usr/src/app
COPY --from=builder /usr/src/app .
USER node
EXPOSE 3000
CMD ["node","src/index.js"]