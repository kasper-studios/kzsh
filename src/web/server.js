const express = require('express');
const path = require('path');
const os = require('os');
const { exec } = require('child_process');

const app = express();

app.use(express.json());
app.use(express.static(path.join(__dirname, '..', '..', 'public')));

// Получение нагрузки CPU (Linux)
function getCpuLoad() {
    return new Promise((resolve) => {
        const cpus = os.cpus();
        let totalIdle = 0, totalTick = 0;
        
        cpus.forEach(cpu => {
            for (const type in cpu.times) {
                totalTick += cpu.times[type];
            }
            totalIdle += cpu.times.idle;
        });
        
        const load = 100 - Math.floor(100 * totalIdle / totalTick);
        resolve(load);
    });
}

// API статус
app.get('/api/status', async (req, res) => {
    const tempReader = require('../core/temperature');
    const powerMgr = require('../core/power');
    const statsMgr = require('../services/stats');
    
    const temperature = await tempReader.getCpuTemperature();
    const load = await getCpuLoad();
    
    res.json({
        temperature,
        load: load.toFixed(1),
        turboEnabled: powerMgr.getTurboState(),
        autoMode: true,
        intelligentMode: true
    });
});

// Ручное управление
app.post('/api/turbo', async (req, res) => {
    const powerMgr = require('../core/power');
    const { enabled } = req.body;
    await powerMgr.setPowerMode(enabled);
    res.json({ success: true, turboEnabled: powerMgr.getTurboState() });
});

// История температуры
app.get('/api/history', (req, res) => {
    const history = require('../services/history');
    res.json(history.getHistory());
});

app.listen(9110, () => {
    console.log('🌐 Web interface on http://localhost:9110');
});