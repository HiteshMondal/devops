const express = require("express");
const os = require("os");

const app = express();
const PORT = process.env.PORT || 3000;
const START_TIME = Date.now();

/* -------------------- Middleware -------------------- */
app.use(express.json());

/* -------------------- Routes -------------------- */

// GUI (Homepage)
app.get("/", (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
      <head>
        <title>DevOps Node App</title>
        <style>
          body {
            font-family: Arial, sans-serif;
            background: #0f172a;
            color: #e5e7eb;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
          }
          .card {
            background: #020617;
            padding: 30px;
            border-radius: 12px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.5);
            width: 400px;
          }
          h1 {
            color: #38bdf8;
          }
          .info {
            margin-top: 15px;
            line-height: 1.6;
          }
          footer {
            margin-top: 20px;
            font-size: 12px;
            color: #94a3b8;
          }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>🚀 DevOps Node.js App</h1>
          <div class="info">
            <p><b>Status:</b> Running</p>
            <p><b>Hostname:</b> ${os.hostname()}</p>
            <p><b>Platform:</b> ${os.platform()}</p>
            <p><b>Uptime:</b> ${Math.floor(
              (Date.now() - START_TIME) / 1000
            )} seconds</p>
          </div>
          <footer>
            Kubernetes • Docker • CI/CD • Terraform
          </footer>
        </div>
      </body>
    </html>
  `);
});

// Health check (K8s readiness/liveness)
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "UP",
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  });
});

// Simple metrics endpoint (Prometheus-friendly)
app.get("/metrics", (req, res) => {
  const memoryUsage = process.memoryUsage();

  res.type("text/plain").send(`
node_app_uptime_seconds ${process.uptime()}
node_app_memory_rss ${memoryUsage.rss}
node_app_memory_heap_used ${memoryUsage.heapUsed}
`);
});

/* -------------------- Server -------------------- */
app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
});
