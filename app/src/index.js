const express = require("express");
const morgan = require("morgan");
const os = require("os");

const app = express();
const PORT = process.env.PORT || 3000;
const START_TIME = Date.now();
const ENV = process.env.NODE_ENV || "development";

// CI/CD metadata (optional)
const BUILD_ID = process.env.BUILD_ID || "local";
const GIT_COMMIT = process.env.GIT_COMMIT || "unknown";

// STATE (in-memory)
let totalRequests = 0;
let totalErrors = 0;
let routeStats = {};
let chaosEnabled = false;
let requestHistory = [];
let alerts = [];

// MIDDLEWARE
app.use(morgan("combined"));
app.use(express.json());

app.use((req, res, next) => {
  const start = Date.now();
  totalRequests++;

  routeStats[req.path] = routeStats[req.path] || {
    count: 0,
    errors: 0,
    avgTime: 0,
    lastAccess: null,
  };
  routeStats[req.path].count++;
  routeStats[req.path].lastAccess = new Date().toISOString();

  // Chaos engineering
  if (chaosEnabled && Math.random() < 0.3) {
    totalErrors++;
    routeStats[req.path].errors++;
    addAlert("error", `Chaos failure on ${req.path}`);
    return res.status(500).json({ error: "Chaos failure injected 💥" });
  }

  res.on("finish", () => {
    const duration = Date.now() - start;
    routeStats[req.path].avgTime =
      (routeStats[req.path].avgTime + duration) / 2;

    if (res.statusCode >= 500) {
      totalErrors++;
      routeStats[req.path].errors++;
      addAlert("error", `Error ${res.statusCode} on ${req.path}`);
    }

    // Track request history (keep last 50)
    requestHistory.unshift({
      path: req.path,
      method: req.method,
      status: res.statusCode,
      duration,
      timestamp: new Date().toISOString(),
    });
    if (requestHistory.length > 50) requestHistory.pop();
  });

  next();
});

// UTILITIES
const uptime = () => Math.floor((Date.now() - START_TIME) / 1000);
const mb = (b) => (b / 1024 / 1024).toFixed(2);

const addAlert = (type, message) => {
  alerts.unshift({ type, message, timestamp: new Date().toISOString() });
  if (alerts.length > 20) alerts.pop();
};

// ROUTES
app.get("/health", (req, res) => {
  res.json({ status: "UP", uptime: uptime() });
});

app.get("/ready", (req, res) => {
  res.json({ status: "READY" });
});

app.get("/metrics", (req, res) => {
  const mem = process.memoryUsage();
  res.json({
    app: "devops-app",
    uptime_seconds: uptime(),
    requests_total: totalRequests,
    errors_total: totalErrors,
    chaos_enabled: chaosEnabled,
    memory_mb: {
      heapUsed: mb(mem.heapUsed),
      heapTotal: mb(mem.heapTotal),
      rss: mb(mem.rss),
    },
    cpu: {
      cores: os.cpus().length,
      load_avg: os.loadavg(),
    },
    routes: routeStats,
    requestHistory: requestHistory.slice(0, 10),
    alerts: alerts.slice(0, 5),
  });
});

app.get("/api/info", (req, res) => {
  res.json({
    environment: ENV,
    node: process.version,
    hostname: os.hostname(),
    platform: os.platform(),
    build_id: BUILD_ID,
    git_commit: GIT_COMMIT,
    memory: {
      total: mb(os.totalmem()),
      free: mb(os.freemem()),
    },
  });
});

app.post("/chaos/:state", (req, res) => {
  chaosEnabled = req.params.state === "on";
  addAlert("info", `Chaos mode ${chaosEnabled ? "enabled" : "disabled"}`);
  res.json({ chaosEnabled });
});

app.post("/reset-stats", (req, res) => {
  totalRequests = 0;
  totalErrors = 0;
  routeStats = {};
  requestHistory = [];
  addAlert("info", "Statistics reset");
  res.json({ message: "Stats reset successfully" });
});

app.delete("/alerts", (req, res) => {
  alerts = [];
  res.json({ message: "Alerts cleared" });
});

app.post("/shutdown", (req, res) => {
  res.json({ message: "Shutting down gracefully..." });
  process.exit(0);
});

// DASHBOARD UI
app.get("/", (req, res) => {
  res.send(`
<!DOCTYPE html>
<html>
<head>
  <title>DevOps Control Panel</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body {
      background:#0f172a;
      color:#e5e7eb;
      font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;
    }
    header {
      padding:24px;
      background:linear-gradient(135deg,#1e293b,#0f172a);
      border-bottom:2px solid #38bdf8;
      position:sticky;
      top:0;
      z-index:100;
      box-shadow:0 4px 6px rgba(0,0,0,.3);
    }
    header h1 {
      font-size:28px;
      color:#38bdf8;
      display:flex;
      align-items:center;
      gap:12px;
    }
    .status-badge {
      font-size:12px;
      padding:4px 12px;
      border-radius:20px;
      background:#10b981;
      color:#fff;
      font-weight:bold;
    }
    .container { padding:20px; max-width:1600px; margin:0 auto; }
    .grid {
      display:grid;
      grid-template-columns:repeat(auto-fit,minmax(320px,1fr));
      gap:20px;
      margin-bottom:20px;
    }
    .card {
      background:#1e293b;
      padding:20px;
      border-radius:12px;
      border:1px solid #334155;
      box-shadow:0 4px 6px rgba(0,0,0,.2);
    }
    .card h3 {
      color:#38bdf8;
      margin-bottom:16px;
      font-size:18px;
      display:flex;
      align-items:center;
      gap:8px;
    }
    .stat-row {
      display:flex;
      justify-content:space-between;
      padding:8px 0;
      border-bottom:1px solid #334155;
    }
    .stat-row:last-child { border:none; }
    .stat-value {
      color:#38bdf8;
      font-weight:bold;
    }
    button {
      padding:10px 16px;
      background:#38bdf8;
      border:none;
      border-radius:8px;
      cursor:pointer;
      font-weight:600;
      color:#020617;
      transition:all .2s;
      margin:4px;
    }
    button:hover { background:#0ea5e9; transform:translateY(-1px); }
    .danger { background:#ef4444; color:#fff; }
    .danger:hover { background:#dc2626; }
    .success { background:#10b981; color:#fff; }
    .success:hover { background:#059669; }
    .warning { background:#f59e0b; color:#fff; }
    .warning:hover { background:#d97706; }
    pre {
      font-size:12px;
      overflow:auto;
      background:#0f172a;
      padding:12px;
      border-radius:6px;
      max-height:200px;
    }
    .alert {
      padding:12px;
      margin:8px 0;
      border-radius:6px;
      border-left:4px solid;
      display:flex;
      justify-content:space-between;
      align-items:center;
      animation:slideIn .3s;
    }
    @keyframes slideIn {
      from { opacity:0; transform:translateX(-20px); }
      to { opacity:1; transform:translateX(0); }
    }
    .alert.error { background:#7f1d1d; border-color:#ef4444; }
    .alert.info { background:#1e3a8a; border-color:#3b82f6; }
    .alert.success { background:#14532d; border-color:#10b981; }
    .chart-bar {
      height:24px;
      background:#38bdf8;
      border-radius:4px;
      margin:8px 0;
      transition:width .3s;
      position:relative;
    }
    .chart-label {
      position:absolute;
      right:8px;
      line-height:24px;
      color:#020617;
      font-weight:bold;
      font-size:12px;
    }
    .request-item {
      padding:8px;
      margin:4px 0;
      background:#0f172a;
      border-radius:4px;
      display:flex;
      justify-content:space-between;
      font-size:12px;
    }
    .method { 
      padding:2px 6px;
      border-radius:4px;
      font-weight:bold;
      background:#334155;
    }
    .status-200 { color:#10b981; }
    .status-500 { color:#ef4444; }
    .full-width { grid-column:1/-1; }
  </style>
</head>
<body>

<header>
  <h1>
    <span>🚀</span>
    DevOps Control Panel
    <span class="status-badge" id="statusBadge">ONLINE</span>
  </h1>
</header>

<div class="container">
  
  <div class="grid">
    
    <div class="card">
      <h3>📊 Performance Metrics</h3>
      <div class="stat-row">
        <span>Uptime</span>
        <span class="stat-value" id="uptime">-</span>
      </div>
      <div class="stat-row">
        <span>Total Requests</span>
        <span class="stat-value" id="req">-</span>
      </div>
      <div class="stat-row">
        <span>Errors</span>
        <span class="stat-value" id="err">-</span>
      </div>
      <div class="stat-row">
        <span>Success Rate</span>
        <span class="stat-value" id="successRate">-</span>
      </div>
    </div>

    <div class="card">
      <h3>💻 System Info</h3>
      <div class="stat-row">
        <span>Hostname</span>
        <span class="stat-value">${os.hostname()}</span>
      </div>
      <div class="stat-row">
        <span>Node Version</span>
        <span class="stat-value">${process.version}</span>
      </div>
      <div class="stat-row">
        <span>CPU Cores</span>
        <span class="stat-value">${os.cpus().length}</span>
      </div>
      <div class="stat-row">
        <span>Platform</span>
        <span class="stat-value">${os.platform()}</span>
      </div>
    </div>

    <div class="card">
      <h3>🎛️ Controls</h3>
      <button onclick="toggleChaos(true)" class="warning">🔥 Enable Chaos</button>
      <button onclick="toggleChaos(false)" class="success">✓ Disable Chaos</button>
      <button onclick="resetStats()">🔄 Reset Stats</button>
      <button onclick="clearAlerts()">🧹 Clear Alerts</button>
    </div>

    <div class="card">
      <h3>🧠 Memory Usage (MB)</h3>
      <div class="stat-row">
        <span>Heap Used</span>
        <span class="stat-value" id="heapUsed">-</span>
      </div>
      <div class="stat-row">
        <span>Heap Total</span>
        <span class="stat-value" id="heapTotal">-</span>
      </div>
      <div class="stat-row">
        <span>RSS</span>
        <span class="stat-value" id="rss">-</span>
      </div>
    </div>

  </div>

  <div class="grid">
    
    <div class="card">
      <h3>🚨 Recent Alerts</h3>
      <div id="alerts">No alerts</div>
    </div>

    <div class="card">
      <h3>📈 Top Routes by Requests</h3>
      <div id="topRoutes">Loading...</div>
    </div>

  </div>

  <div class="grid">
    
    <div class="card full-width">
      <h3>📜 Recent Requests</h3>
      <div id="recentRequests">Loading...</div>
    </div>

    <div class="card full-width">
      <h3>🗺️ Route Statistics</h3>
      <pre id="routes">Loading...</pre>
    </div>

  </div>

</div>

<script>
let refreshInterval;

async function refresh() {
  try {
    const res = await fetch('/metrics');
    const data = await res.json();
    
    // Update stats
    document.getElementById('uptime').innerText = formatUptime(data.uptime_seconds);
    document.getElementById('req').innerText = data.requests_total.toLocaleString();
    document.getElementById('err').innerText = data.errors_total.toLocaleString();
    
    const successRate = data.requests_total > 0 
      ? (((data.requests_total - data.errors_total) / data.requests_total) * 100).toFixed(1)
      : 100;
    document.getElementById('successRate').innerText = successRate + '%';
    
    // Memory
    document.getElementById('heapUsed').innerText = data.memory_mb.heapUsed;
    document.getElementById('heapTotal').innerText = data.memory_mb.heapTotal;
    document.getElementById('rss').innerText = data.memory_mb.rss;
    
    // Routes
    document.getElementById('routes').innerText = JSON.stringify(data.routes, null, 2);
    
    // Alerts
    const alertsDiv = document.getElementById('alerts');
    if (data.alerts && data.alerts.length > 0) {
      alertsDiv.innerHTML = data.alerts.map(a => 
        \`<div class="alert \${a.type}">
          <span>\${a.message}</span>
          <small>\${new Date(a.timestamp).toLocaleTimeString()}</small>
        </div>\`
      ).join('');
    } else {
      alertsDiv.innerHTML = '<p style="opacity:.5">No recent alerts</p>';
    }
    
    // Recent requests
    const reqDiv = document.getElementById('recentRequests');
    if (data.requestHistory && data.requestHistory.length > 0) {
      reqDiv.innerHTML = data.requestHistory.map(r => 
        \`<div class="request-item">
          <div>
            <span class="method">\${r.method}</span>
            <span>\${r.path}</span>
          </div>
          <div>
            <span class="status-\${r.status}">\${r.status}</span>
            <span style="opacity:.7"> • \${r.duration}ms</span>
          </div>
        </div>\`
      ).join('');
    }
    
    // Top routes chart
    const sortedRoutes = Object.entries(data.routes)
      .sort((a, b) => b[1].count - a[1].count)
      .slice(0, 5);
    
    const maxCount = sortedRoutes[0]?.[1].count || 1;
    const topRoutesDiv = document.getElementById('topRoutes');
    if (sortedRoutes.length > 0) {
      topRoutesDiv.innerHTML = sortedRoutes.map(([path, stats]) => {
        const width = (stats.count / maxCount) * 100;
        return \`<div>
          <small>\${path}</small>
          <div class="chart-bar" style="width:\${width}%">
            <span class="chart-label">\${stats.count}</span>
          </div>
        </div>\`;
      }).join('');
    }
    
  } catch (err) {
    console.error('Refresh failed:', err);
    document.getElementById('statusBadge').innerText = 'ERROR';
    document.getElementById('statusBadge').style.background = '#ef4444';
  }
}

function formatUptime(seconds) {
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;
  
  if (days > 0) return \`\${days}d \${hours}h\`;
  if (hours > 0) return \`\${hours}h \${mins}m\`;
  if (mins > 0) return \`\${mins}m \${secs}s\`;
  return \`\${secs}s\`;
}

async function toggleChaos(state) {
  await fetch('/chaos/' + (state ? 'on' : 'off'), { method:'POST' });
  refresh();
}

async function resetStats() {
  if (confirm('Reset all statistics?')) {
    await fetch('/reset-stats', { method:'POST' });
    refresh();
  }
}

async function clearAlerts() {
  await fetch('/alerts', { method:'DELETE' });
  refresh();
}

refresh();
refreshInterval = setInterval(refresh, 3000);

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
  clearInterval(refreshInterval);
});
</script>

</body>
</html>
`);
});

// GRACEFUL SHUTDOWN
process.on("SIGTERM", () => {
  console.log("SIGTERM received. Shutting down...");
  process.exit(0);
});

app.listen(PORT, () =>
  console.log(`🚀 DevOps App running on port ${PORT}`)
);