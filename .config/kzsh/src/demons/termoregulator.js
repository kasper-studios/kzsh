#!/usr/bin/env node
const express = require('express');
const path = require('path');
const os = require('os');
const fs = require('fs');
const { exec } = require('child_process');

const {
    PORT,
    TEMP_THRESHOLD,
    TEMP_HIGH,
    TEMP_SAFE,
    IDLE_LOAD_THRESHOLD,
    COOLDOWN
} = require('../config/constants');

const app = express();
app.use(express.json());

// Поиск public директории - ищем public рядом с .config/kzsh или в корне репо
let publicPath;
const configDir = path.dirname(path.dirname(__dirname)); // .config/kzsh
const repoDir = path.dirname(configDir); // .kzsh-repo

if (fs.existsSync(path.join(repoDir, 'public'))) {
    publicPath = path.join(repoDir, 'public');
} else if (fs.existsSync(path.join(configDir, 'public'))) {
    publicPath = path.join(configDir, 'public');
} else {
    publicPath = path.join(configDir, 'src', '..', '..', 'public');
}
app.use(express.static(publicPath));

const logDir = path.join(__dirname, '..', '.logs');
if (!fs.existsSync(logDir)) {
    fs.mkdirSync(logDir, { recursive: true });
}

let autoMode = false;
let lastBoostChange = Date.now();
let turboEnabled = false;

function getCpuLoad() {
    const cpus = os.cpus();
    const idle = cpus.reduce((acc, c) => acc + Object.values(c.times).reduce((a, b) => a + b, 0), 0);
    const total = cpus.reduce((acc, c) => acc + Object.values(c.times).reduce((a, b) => a + b, 0), 0);
    return 100 - Math.round(100 * idle / total);
}

function getCpuTemperature() {
    try {
        const zones = fs.readdirSync('/sys/class/thermal').filter(f => f.startsWith('thermal_zone'));
        for (const zone of zones) {
            const temp = parseInt(fs.readFileSync(`/sys/class/thermal/${zone}/temp`, 'utf8').trim());
            if (!isNaN(temp) && temp > 0) return temp / 1000;
        }
    } catch (e) {}
    return null;
}

async function setPowerMode(isMax) {
    const profile = isMax ? 'performance' : 'power-saver';
    await execAsync(`powerprofilesctl set ${profile}`);
    turboEnabled = isMax;
    lastBoostChange = Date.now();
}

function execAsync(cmd) {
    return new Promise((resolve, reject) => {
        exec(cmd, (err) => err ? reject(err) : resolve());
    });
}

function canChange() {
    return Date.now() - lastBoostChange > COOLDOWN;
}

app.get('/', (req, res) => {
    const indexFile = path.join(publicPath, 'index.html');
    if (fs.existsSync(indexFile)) {
        res.sendFile(indexFile);
    } else {
        res.send(`<h1>Teremoregulator running</h1><p>publicPath: ${publicPath}</p><pre>${JSON.stringify({temp: getCpuTemperature(), load: getCpuLoad()}, null, 2)}</pre>`);
    }
});

app.get('/widget', (req, res) => {
    const widgetFile = path.join(publicPath, 'widget.html');
    if (fs.existsSync(widgetFile)) {
        res.sendFile(widgetFile);
    } else {
        res.json({ error: 'widget.html not found', publicPath, temp: getCpuTemperature() });
    }
});

app.get('/api/status', async (req, res) => {
    const temp = getCpuTemperature();
    const load = getCpuLoad();
    res.json({ temperature: temp, load, turboEnabled, autoMode, profile: turboEnabled ? 'performance' : 'power-saver' });
});

app.post('/api/turbo', async (req, res) => {
    const { enabled } = req.body;
    await setPowerMode(enabled);
    res.json({ success: true, turboEnabled });
});

app.post('/api/auto', (req, res) => {
    autoMode = req.body.enabled;
    res.json({ success: true, autoMode });
});

setInterval(async () => {
    if (!autoMode) return;
    const temp = getCpuTemperature();
    const load = getCpuLoad();
    if (!temp || !canChange()) return;
    if (temp > TEMP_HIGH && turboEnabled) {
        console.log(`🔥 ${temp}°C - выключаю буст`);
        await setPowerMode(false);
    } else if (load >= IDLE_LOAD_THRESHOLD && temp < TEMP_SAFE && !turboEnabled) {
        console.log(`⚡ Нагрузка ${load}% + температура ${temp}°C - включаю буст`);
        await setPowerMode(true);
    }
}, 2000);

app.listen(PORT, () => {
    console.log(`\n🌡️ темп регулятор запущен на http://localhost:${PORT}`);
    console.log(`📁 publicPath: ${publicPath}`);
});