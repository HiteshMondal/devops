const express = require('express');
const os = require('os');
const app = express();
const port = process.env.PORT || 3000;


app.get('/', (req, res) => {
res.json({
message: 'Hello from production-ready scaffold',
hostname: os.hostname(),
uptime: process.uptime()
});
});


app.get('/healthz', (req, res) => {
res.status(200).send('OK');
});


app.listen(port, () => console.log(`Server running on :${port}`));