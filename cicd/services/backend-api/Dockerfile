################################################################################
# 5. DOCKERFILE - BACKEND API (Multi-stage Build)
################################################################################
---
# File: services/backend-api/Dockerfile
# Stage 1: Dependencies
FROM node:20-alpine AS dependencies
WORKDIR /app

# Install security updates
RUN apk add --no-cache --upgrade \
    && apk add --no-cache dumb-init

# Copy package files
COPY package*.json ./
COPY .npmrc* ./

# Install production dependencies
RUN npm ci --only=production --ignore-scripts \
    && npm cache clean --force

# Stage 2: Build
FROM node:20-alpine AS builder
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install all dependencies (including devDependencies)
RUN npm ci --ignore-scripts

# Copy source code
COPY . .

# Build application
RUN npm run build \
    && npm prune --production

# Stage 3: Production
FROM node:20-alpine AS production
WORKDIR /app

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init curl

# Create non-root user
RUN addgroup -g 1001 -S nodejs \
    && adduser -S nodejs -u 1001

# Copy dependencies from dependencies stage
COPY --from=dependencies --chown=nodejs:nodejs /app/node_modules ./node_modules

# Copy built application from builder stage
COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist
COPY --from=builder --chown=nodejs:nodejs /app/package*.json ./

# Set build-time metadata
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.title="Backend API" \
      org.opencontainers.image.description="Production-ready Backend API" \
      org.opencontainers.image.authors="DevOps Team <devops@example.com>" \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.vendor="Example Corp"

# Switch to non-root user
USER nodejs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD node dist/healthcheck.js || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]

# Start application
CMD ["node", "dist/server.js"]