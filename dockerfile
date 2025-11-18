# Multi-stage Dockerfile for production-ready deployment
# Stage 1: Build stage with Node.js for any preprocessing
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /build

# Copy package files (create dummy ones for this example)
COPY package*.json ./

# Install dependencies if any
RUN npm ci --only=production 2>/dev/null || echo "No npm dependencies"

# Copy application files
COPY . .

# Run any build steps (minification, etc.)
RUN echo "Build stage completed"

# Stage 2: Production stage with Nginx
FROM nginx:alpine

# Install necessary packages for health checks
RUN apk add --no-cache curl tzdata

# Set timezone
ENV TZ=UTC

# Remove default nginx static content
RUN rm -rf /usr/share/nginx/html/*

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/conf.d/default.conf

# Copy static files from builder stage
COPY --from=builder /build/app.html /usr/share/nginx/html/


# Add health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost/3000 || exit 1

# Create non-root user
RUN addgroup -g 1001 -S nginx-group && \
    adduser -S -D -H -u 1001 -s /bin/sh -G nginx-group nginx-user && \
    chown -R nginx-user:nginx-group /usr/share/nginx/html && \
    chown -R nginx-user:nginx-group /var/cache/nginx && \
    chown -R nginx-user:nginx-group /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown -R nginx-user:nginx-group /var/run/nginx.pid

# Switch to non-root user
USER nginx-user

# Expose port
EXPOSE 3000

# Labels for image metadata
LABEL maintainer="DevOps Team"
LABEL version="1.0.0"
LABEL description="Production-ready web application with nginx"

# Start nginx
CMD ["nginx", "-g", "daemon off;"]