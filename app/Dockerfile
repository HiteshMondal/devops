#  Stage 1: Build 
FROM node:18-alpine AS builder

WORKDIR /build

# Copy dependency files first (cache-friendly)
COPY package*.json tsconfig.json ./

# Install ALL dependencies (including devDependencies for tsc)
RUN npm install

# Copy source
COPY src ./src

# Compile TypeScript → JavaScript
RUN npm run build

# Stage 2: Runtime 
FROM node:18-alpine

# Create non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy dependency manifest and install production deps only
COPY package*.json ./
RUN npm install --production

# Copy compiled output from builder stage
COPY --from=builder /build/dist ./dist

# Fix permissions
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Expose application port
EXPOSE 3000

# Start compiled application
CMD ["node", "dist/index.js"]