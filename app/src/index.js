const express = require("express");
const morgan = require("morgan");
const os = require("os");
const app = express();
const PORT = process.env.PORT || 3000;
const START_TIME = Date.now();
const ENV = process.env.NODE_ENV || "development";

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

app.get("/", (req, res) => {
  res.send(`
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DevOps Panel</title>
<style>
body{
  margin:0;
  font-family:system-ui,Arial;
  background:#0f172a;
  color:#e5e7eb
}
header{
  padding:16px;
  background:#020617;
  border-bottom:1px solid #334155
}
h1{font-size:20px;color:#38bdf8}

.container{
  max-width:1200px;
  margin:auto;
  padding:16px
}
.grid{
  display:grid;
  gap:16px;
  grid-template-columns:repeat(auto-fit,minmax(260px,1fr))
}
.card{
  background:#1e293b;
  padding:16px;
  border:1px solid #334155;
  border-radius:8px
}
.row{
  display:flex;
  justify-content:space-between;
  padding:6px 0;
  border-bottom:1px solid #334155
}
.row:last-child{border:0}
.val{color:#38bdf8;font-weight:600}
</style>
</head>

<body>
<header>
  <h1>DevOps Control Panel</h1>
</header>

<div class="container">
  <div class="grid">

    <div class="card">
      <h3>Performance</h3>
      <div class="row"><span>Uptime</span><span class="val" id="uptime">-</span></div>
      <div class="row"><span>Requests</span><span class="val" id="req">-</span></div>
      <div class="row"><span>Errors</span><span class="val" id="err">-</span></div>
    </div>

    <div class="card">
      <h3>System</h3>
      <div class="row"><span>Host</span><span class="val">${os.hostname()}</span></div>
      <div class="row"><span>Node</span><span class="val">${process.version}</span></div>
      <div class="row"><span>CPU</span><span class="val">${os.cpus().length}</span></div>
    </div>

    <div class="card">
      <h3>Memory (MB)</h3>
      <div class="row"><span>Heap Used</span><span class="val" id="heapUsed">-</span></div>
      <div class="row"><span>Heap Total</span><span class="val" id="heapTotal">-</span></div>
      <div class="row"><span>RSS</span><span class="val" id="rss">-</span></div>
    </div>

  </div>
</div>
</body>
</html>

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