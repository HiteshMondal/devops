require('dotenv').config();
const express = require('express');
const morgan = require('morgan');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());
app.use(morgan('combined'));

// Routes
app.get('/', (req, res) => {
  res.json({ message: 'Hello from DevOps App!', env: process.env.NODE_ENV || 'development' });
});

// Health check (for Kubernetes liveness/readiness probes)
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'UP' });
});

// Sample API route
app.get('/api/info', (req, res) => {
  res.json({
    app: 'DevOps Sample App',
    version: '1.0.0',
    uptime: process.uptime(),
    timestamp: new Date()
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`App running on port ${PORT} in ${process.env.NODE_ENV || 'development'} mode`);
});
