const express = require('express');
const morgan = require('morgan');
const promClient = require('prom-client');

const app = express();
const PORT = process.env.APP_PORT || 3000;

// PROMETHEUS METRICS CONFIGURATION

// Create a Registry to register the metrics
const register = new promClient.Registry();

// Add default metrics (CPU, memory, event loop, etc.)
promClient.collectDefaultMetrics({ 
  register,
  prefix: 'nodejs_',
  gcDurationBuckets: [0.001, 0.01, 0.1, 1, 2, 5]
});

// Custom metrics
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.001, 0.005, 0.015, 0.05, 0.1, 0.5, 1, 5]
});

const httpRequestTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});

const activeConnections = new promClient.Gauge({
  name: 'http_active_connections',
  help: 'Number of active HTTP connections'
});

const appUptime = new promClient.Gauge({
  name: 'app_uptime_seconds',
  help: 'Application uptime in seconds'
});

const appInfo = new promClient.Gauge({
  name: 'app_info',
  help: 'Application information',
  labelNames: ['version', 'name', 'env']
});

// Register custom metrics
register.registerMetric(httpRequestDuration);
register.registerMetric(httpRequestTotal);
register.registerMetric(activeConnections);
register.registerMetric(appUptime);
register.registerMetric(appInfo);

// Set app info
appInfo.set({ 
  version: process.env.APP_VERSION || '1.0.0', 
  name: process.env.APP_NAME || 'devops-app',
  env: process.env.NODE_ENV || 'development'
}, 1);

// Update uptime periodically
const startTime = Date.now();
setInterval(() => {
  appUptime.set((Date.now() - startTime) / 1000);
}, 1000);

// MIDDLEWARE

// Logging middleware
app.use(morgan('combined'));

// Parse JSON bodies
app.use(express.json());

// Metrics collection middleware
app.use((req, res, next) => {
  activeConnections.inc();
  const start = Date.now();

  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const route = req.route ? req.route.path : req.path;
    const labels = {
      method: req.method,
      route: route,
      status_code: res.statusCode
    };

    httpRequestDuration.observe(labels, duration);
    httpRequestTotal.inc(labels);
    activeConnections.dec();
  });

  next();
});

// ROUTES

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ 
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Readiness endpoint
app.get('/ready', (req, res) => {
  res.status(200).json({ 
    status: 'ready',
    timestamp: new Date().toISOString()
  });
});

// Metrics endpoint for Prometheus
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'DevOps Application is running!',
    version: process.env.APP_VERSION || '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    timestamp: new Date().toISOString()
  });
});

// API endpoints for testing
app.get('/api/status', (req, res) => {
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    cpu: process.cpuUsage()
  });
});

// Simulate some load for testing metrics
app.get('/api/slow', async (req, res) => {
  const delay = Math.random() * 2000; // Random delay up to 2 seconds
  await new Promise(resolve => setTimeout(resolve, delay));
  res.json({ 
    message: 'Slow endpoint',
    delay: `${delay}ms`
  });
});

app.post('/api/data', (req, res) => {
  res.status(201).json({
    message: 'Data received',
    data: req.body,
    timestamp: new Date().toISOString()
  });
});

// Error handling
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(500).json({
    error: 'Internal Server Error',
    message: err.message
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    path: req.path
  });
});

// SERVER STARTUP
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log('='.repeat(80));
  console.log(`🚀 DevOps Application Started`);
  console.log('='.repeat(80));
  console.log(`📍 Server: http://0.0.0.0:${PORT}`);
  console.log(`🏥 Health: http://0.0.0.0:${PORT}/health`);
  console.log(`📊 Metrics: http://0.0.0.0:${PORT}/metrics`);
  console.log(`🌐 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log('='.repeat(80));
});

// Graceful shutdown
const shutdown = (signal) => {
  console.log(`\n${signal} received. Starting graceful shutdown...`);
  server.close(() => {
    console.log('✅ HTTP server closed');
    process.exit(0);
  });

  // Force shutdown after 10 seconds
  setTimeout(() => {
    console.error('⚠️  Forced shutdown after timeout');
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

module.exports = app;