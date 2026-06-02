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
    try {
        const cpus = os.cpus();
        let totalIdle = 0;
        let totalTick = 0;
        
        cpus.forEach(cpu => {
            for (const type in cpu.times) {
                totalTick += cpu.times[type];
            }
            totalIdle += cpu.times.idle;
        });
        
        const idle = totalIdle / cpus.length;
        const total = totalTick / cpus.length;
        const usage = 100 - ~~(100 * idle / total);
        
        return Math.max(0, Math.min(usage, 100));
    } catch (e) {
        return 0;
    }
}


function getCpuTemperature() {
    try {
        const zones = fs.readdirSync('/sys/class/thermal').filter(f => f.startsWith('thermal_zone'));
        let maxTemp = 0;
        for (const zone of zones) {
            const temp = parseInt(fs.readFileSync(`/sys/class/thermal/${zone}/temp`, 'utf8').trim());
            if (!isNaN(temp) && temp > 0) {
                const tempC = temp / 1000;
                maxTemp = Math.max(maxTemp, tempC);
            }
        }
        return maxTemp > 0 ? maxTemp : null;
    } catch (e) {}
    return null;
}

function getBatteryInfo() {
    try {
        const batteryPath = '/sys/class/power_supply';
        const supplies = fs.readdirSync(batteryPath);
        
        for (const supply of supplies) {
            if (supply.includes('BAT')) {
                try {
                    const capPath = path.join(batteryPath, supply, 'capacity');
                    const statusPath = path.join(batteryPath, supply, 'status');
                    
                    const capacity = parseInt(fs.readFileSync(capPath, 'utf8').trim());
                    const status = fs.readFileSync(statusPath, 'utf8').trim();
                    
                    return {
                        capacity,
                        status: status.toLowerCase(),
                        isCharging: status.includes('Charging')
                    };
                } catch (e) {
                    continue;
                }
            }
        }
    } catch (e) {}
    return { capacity: 100, status: 'unknown', isCharging: false };
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
    const battery = getBatteryInfo();
    res.json({ 
        temperature: temp, 
        load, 
        turboEnabled, 
        autoMode, 
        profile: turboEnabled ? 'performance' : 'power-saver',
        battery
    });
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
