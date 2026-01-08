# Use official Node.js LTS image
FROM node:18-alpine

# Create a non-root user and group
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Set working directory
WORKDIR /app

# Copy package files first (for caching)
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy app source code
COPY src ./src

# Change ownership of the app folder to the non-root user
RUN chown -R appuser:appgroup /app

# Switch to the non-root user
USER appuser

# Expose app port
EXPOSE 3000

# Start the app
CMD ["npm", "start"]
