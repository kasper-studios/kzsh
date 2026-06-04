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
    COOLDOWN,
    COOLDOWN_DOWN,
    TEMP_TREND_WINDOW,
    TEMP_TREND_RISE_THRESHOLD,
    TEMP_TREND_SAFE_OFFSET
} = require('../config/constants');

const history = require('../services/history');

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
let lastBoostUp = 0;    // когда последний раз ПОВЫШАЛИ профиль (performance)
let lastBoostDown = 0;  // когда последний раз ПОНИЖАЛИ профиль (power-saver)
let turboEnabled = false;
let minTemp = null;
let maxTemp = null;
let sessionStartTime = Date.now();

// Скользящий буфер температур для анализа тренда
const tempBuffer = [];

let lastCpuStats = null;

function getCpuLoad() {
    try {
        const stat = fs.readFileSync('/proc/stat', 'utf8').split('\n')[0];
        const parts = stat.split(/\s+/).slice(1);
        const [user, nice, system, idle, iowait, irq, softirq] = parts.map(Number);
        
        const currentStats = {
            user, nice, system, idle, iowait, irq, softirq,
            total: user + nice + system + idle + iowait + irq + softirq
        };
        
        // При первом вызове просто сохраняем статистику
        if (!lastCpuStats) {
            lastCpuStats = currentStats;
            return 0;
        }
        
        // Вычисляем дельту
        const deltaTotalTime = currentStats.total - lastCpuStats.total;
        const deltaIdleTime = currentStats.idle - lastCpuStats.idle;
        
        // Если нет движения - вернуть 0
        if (deltaTotalTime === 0) {
            return 0;
        }
        
        // Вычисляем процент использования
        const usage = 100 * (deltaTotalTime - deltaIdleTime) / deltaTotalTime;
        lastCpuStats = currentStats;
        
        return Math.max(0, Math.min(Math.round(usage), 100));
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
                        level: capacity,
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
    if (isMax) {
        lastBoostUp = Date.now();
    } else {
        lastBoostDown = Date.now();
    }
}

function execAsync(cmd) {
    return new Promise((resolve, reject) => {
        exec(cmd, (err) => err ? reject(err) : resolve());
    });
}

// Можно ли ПОВЫСИТЬ профиль (строгий cooldown 30 сек)
function canUpgrade() {
    return Date.now() - lastBoostUp > COOLDOWN;
}

// Можно ли ПОНИЗИТЬ профиль (мягкий cooldown 5 сек, 0 при критическом перегреве)
function canDowngrade(temp) {
    if (temp >= TEMP_THRESHOLD) return true; // критический перегрев — немедленно
    return Date.now() - lastBoostDown > COOLDOWN_DOWN;
}

// Вычисляем средний тренд температуры за последние N тиков (°C/тик)
function getTempTrend() {
    if (tempBuffer.length < 2) return 0;
    let totalDelta = 0;
    for (let i = 1; i < tempBuffer.length; i++) {
        totalDelta += tempBuffer[i] - tempBuffer[i - 1];
    }
    return totalDelta / (tempBuffer.length - 1);
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
        minTemp,
        maxTemp,
        load, 
        turboEnabled, 
        autoMode, 
        profile: turboEnabled ? 'performance' : 'power-saver',
        battery
    });
});

app.get('/api/history', (req, res) => {
    res.json(history.getHistory());
});

app.post('/api/history/period', (req, res) => {
    const { period } = req.body;
    if (history.setPeriod(period)) {
        res.json({ success: true, period });
    } else {
        res.status(400).json({ error: 'Invalid period' });
    }
});

app.get('/api/stats', (req, res) => {
    const uptime = Math.floor((Date.now() - sessionStartTime) / 1000);
    res.json({
        minTemp,
        maxTemp,
        maxTemperature: maxTemp,
        avgTemperature: maxTemp || 0,
        totalSessions: 1,
        overheatingPrevented: 0,
        totalRuntime: uptime,
        longestSession: uptime,
        currentSessionTime: uptime,
        owner: 'KZSH',
        sessionUptime: uptime
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
    const temp = getCpuTemperature();
    const load = getCpuLoad();
    
    // Обновляем историю и буфер тренда
    if (temp !== null) {
        // Скользящий буфер для анализа тренда
        tempBuffer.push(temp);
        if (tempBuffer.length > TEMP_TREND_WINDOW) tempBuffer.shift();
        
        history.addToHistory(temp, load, turboEnabled);
        
        // Обновляем min/max температуры
        if (minTemp === null || temp < minTemp) minTemp = temp;
        if (maxTemp === null || temp > maxTemp) maxTemp = temp;
    }
    
    if (!autoMode || !temp) return;
    
    const trend = getTempTrend();
    
    // Адаптивный порог: при быстром росте температуры — срабатываем раньше
    const effectiveHighThreshold = (trend > TEMP_TREND_RISE_THRESHOLD)
        ? TEMP_HIGH - TEMP_TREND_SAFE_OFFSET
        : TEMP_HIGH;
    
    // ПОНИЖЕНИЕ профиля: быстрый cooldown (5 сек), при критическом перегреве — мгновенно
    if (turboEnabled && temp > effectiveHighThreshold && canDowngrade(temp)) {
        const reason = temp >= TEMP_THRESHOLD
            ? `🔥 КРИТИЧЕСКИЙ ПЕРЕГРЕВ ${temp}°C`
            : trend > TEMP_TREND_RISE_THRESHOLD
                ? `🔥 ${temp}°C (тренд +${trend.toFixed(1)}°C/тик, порог снижен до ${effectiveHighThreshold}°C)`
                : `🔥 ${temp}°C превышает ${effectiveHighThreshold}°C`;
        console.log(`${reason} - выключаю буст`);
        await setPowerMode(false);
    }
    // ПОВЫШЕНИЕ профиля: строгий cooldown (30 сек) + температура должна быть безопасной + тренд не растёт
    else if (!turboEnabled && load >= IDLE_LOAD_THRESHOLD && temp < TEMP_SAFE && trend <= 0.5 && canUpgrade()) {
        console.log(`⚡ Нагрузка ${load}% + температура ${temp}°C (тренд: ${trend.toFixed(1)}) - включаю буст`);
        await setPowerMode(true);
    }
}, 2000);

app.listen(PORT, () => {
    console.log(`\n🌡️ темп регулятор запущен на http://localhost:${PORT}`);
    console.log(`📁 publicPath: ${publicPath}`);
});
