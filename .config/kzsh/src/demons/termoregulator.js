const express = require('express');
const path = require('path');
const os = require('os');
const fs = require('fs');
const { exec, execSync } = require('child_process');

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
app.use(express.static(path.resolve(__dirname, '..', '..', 'public')));

// Создание директории логов
const logDir = path.join(__dirname, '..', '.logs');
if (!fs.existsSync(logDir)) {
    fs.mkdirSync(logDir, { recursive: true });
}

// Состояние
let autoMode = false;
let lastBoostChange = Date.now();
let turboEnabled = false;

// Получение нагрузки CPU
function getCpuLoad() {
    const cpus = os.cpus();
    const idle = cpus.reduce((acc, cpu) => acc + Object.values(cpu.times).reduce((a, b) => a + b), 0);
    const total = cpus.reduce((acc, cpu) => acc + Object.values(cpu.times).reduce((a, b) => a + b), 0);
    return 100 - Math.round(100 * idle / total);
}

// Получение температуры
function getCpuTemperature() {
    try {
        const zones = fs.readdirSync('/sys/class/thermal')
            .filter(f => f.startsWith('thermal_zone'));
        for (const zone of zones) {
            const temp = parseInt(fs.readFileSync(`/sys/class/thermal/${zone}/temp`, 'utf8').trim());
            if (!isNaN(temp) && temp > 0) return temp / 1000;
        }
    } catch (e) {}
    
    try {
        const output = execSync('sensors 2>/dev/null | grep -E "(Tctl|Tdie|Package)" | head -1', { encoding: 'utf8' });
        const match = output.match(/([\d,.]+)/);
        return match ? parseFloat(match[1].replace(',', '.')) : null;
    } catch (e) {}
    
    return null;
}

// Управление профилем
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

// API
app.get('/api/status', async (req, res) => {
    const temp = getCpuTemperature();
    const load = getCpuLoad();
    
    res.json({
        temperature: temp,
        load,
        turboEnabled,
        autoMode,
        profile: turboEnabled ? 'performance' : 'power-saver'
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

// Авто контроль при включении
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

// Старт
app.listen(PORT, async () => {
    console.log(`\n🌡️ темп регулятор запущен на http://localhost:${PORT}`);
});