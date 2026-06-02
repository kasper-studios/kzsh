#!/usr/bin/env node
const express = require('express');
const path = require('path');
const os = require('os');
const fs = require('fs');

// Использование Linux-совместимых модулей
const temperatureReader = require('../core/temperature-linux');
const powerManager = require('../core/power-linux');
const {
    PORT,
    TEMP_HIGH,
    TEMP_SAFE,
    IDLE_LOAD_THRESHOLD,
    COOLDOWN
} = require('../config/constants');

const app = express();
app.use(express.json());

// Поиск public директории
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

let autoMode = false;

// Получение нагрузки CPU
const getCpuLoad = () => {
    const avgLoad = os.loadavg()[0];
    const numCpus = os.cpus().length;
    const cpuUsage = (avgLoad / numCpus) * 100;
    return Math.min(cpuUsage, 100);
};

// Получение информации о батарее
const getBatteryInfo = () => {
    return new Promise((resolve) => {
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
                        
                        resolve({
                            capacity,
                            status: status.toLowerCase(),
                            isCharging: status.includes('Charging')
                        });
                        return;
                    } catch (e) {
                        continue;
                    }
                }
            }
            resolve({ capacity: 100, status: 'unknown', isCharging: false });
        } catch (e) {
            resolve({ capacity: 100, status: 'unknown', isCharging: false });
        }
    });
};

// API маршруты
app.get('/', (req, res) => {
    const indexFile = path.join(publicPath, 'index.html');
    if (fs.existsSync(indexFile)) {
        res.sendFile(indexFile);
    } else {
        res.send(`<h1>Termoregulator running</h1><p>publicPath: ${publicPath}</p>`);
    }
});

app.get('/api/status', async (req, res) => {
    const temp = await temperatureReader.getCpuTemperature();
    const load = getCpuLoad();
    const battery = await getBatteryInfo();
    
    res.json({ 
        temperature: temp, 
        load: Math.round(load),
        turboEnabled: powerManager.getTurboState(),
        autoMode,
        profile: powerManager.currentProfile,
        battery
    });
});

app.post('/api/turbo', async (req, res) => {
    const { enabled } = req.body;
    await powerManager.setPowerMode(enabled);
    res.json({ success: true, turboEnabled: powerManager.getTurboState() });
});

app.post('/api/auto', (req, res) => {
    autoMode = req.body.enabled;
    res.json({ success: true, autoMode });
});

// Автоматический контроль температуры
setInterval(async () => {
    if (!autoMode) return;
    
    const temp = await temperatureReader.getCpuTemperature();
    const load = getCpuLoad();
    
    if (!temp || !powerManager.canChange()) return;
    
    if (temp > TEMP_HIGH && powerManager.getTurboState()) {
        console.log(`🔥 ${temp.toFixed(1)}°C - отключаю буст`);
        await powerManager.setPowerMode(false);
    } else if (load >= IDLE_LOAD_THRESHOLD && temp < TEMP_SAFE && !powerManager.getTurboState()) {
        console.log(`⚡ Нагрузка ${Math.round(load)}% + температура ${temp.toFixed(1)}°C - включаю буст`);
        await powerManager.setPowerMode(true);
    }
}, 2000);

app.listen(PORT, async () => {
    await powerManager.applyOnStartup();
    console.log(`\n🌡️ терморегулятор запущен на http://localhost:${PORT}`);
    console.log(`📁 publicPath: ${publicPath}`);
});
