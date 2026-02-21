# /app/Dockerfile

# Use official Node.js LTS image
FROM node:18-alpine

# Create non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Set working directory
WORKDIR /app

# Copy dependency files first (cache-friendly)
COPY package*.json ./

# Install production dependencies
RUN npm install --production

# Copy full app source
COPY . .

# Fix permissions
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Expose application port
EXPOSE 3000

# Start application
CMD ["node", "src/index.js"]
