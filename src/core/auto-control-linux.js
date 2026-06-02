const powerManager = require('./power-linux');
const batteryManager = require('../core/battery-linux');
const processManager = require('../core/processes-linux');
const statsManager = require('../services/stats');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const {
    TEMP_THRESHOLD,
    TEMP_HIGH,
    TEMP_SAFE,
    IDLE_LOAD_THRESHOLD,
    IDLE_TEMP_THRESHOLD,
    HIGH_LOAD_THRESHOLD,
    TEMP_HISTORY_SIZE,
    PROCESS_CHECK_INTERVAL,
    BOOST_PROCESSES
} = require('../config/constants');

class AutoControl {
    constructor() {
        this.autoMode = true;
        this.intelligentMode = true;
        this.tempHistory = [];
        this.lastProcessCheck = 0;
        this.detectedProcesses = [];
        this.configPath = path.join(__dirname, '..', '..', '.config', 'auto-mode.json');
        this.loadConfig();
    }

    loadConfig() {
        try {
            if (fs.existsSync(this.configPath)) {
                const data = JSON.parse(fs.readFileSync(this.configPath, 'utf8'));
                if (typeof data.autoMode === 'boolean') this.autoMode = data.autoMode;
                if (typeof data.intelligentMode === 'boolean') this.intelligentMode = data.intelligentMode;
            }
        } catch (e) {}
    }

    saveConfig() {
        try {
            const dir = path.dirname(this.configPath);
            if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
            fs.writeFileSync(this.configPath, JSON.stringify({
                autoMode: this.autoMode,
                intelligentMode: this.intelligentMode
            }, null, 2));
        } catch (e) {}
    }

    getBaseProfile(temp, load) {
        if (temp > 87) return 'power-saver';
        if (temp >= 80) return 'balanced';
        if (temp < 80 && load > 50) return 'performance';
        return 'balanced';
    }

    analyzeTempTrend(currentTemp) {
        this.tempHistory.push(currentTemp);
        if (this.tempHistory.length > TEMP_HISTORY_SIZE) this.tempHistory.shift();
        if (this.tempHistory.length < 3) return { trend: 'unknown', rate: 0 };

        const oldTemp = this.tempHistory[0];
        const rate = (currentTemp - oldTemp) / this.tempHistory.length;

        let trend = 'stable';
        if (rate > 1) trend = 'rising-fast';
        else if (rate > 0.5) trend = 'rising';
        else if (rate < -1) trend = 'falling-fast';
        else if (rate < -0.5) trend = 'falling';

        return { trend, rate: rate.toFixed(2) };
    }

    async detectBoostProcesses() {
        const now = Date.now();
        if (now - this.lastProcessCheck < PROCESS_CHECK_INTERVAL) {
            return this.detectedProcesses;
        }
        this.lastProcessCheck = now;
        this.detectedProcesses = [];
        try {
            const { stdout } = await new Promise((resolve) => {
                exec('ps aux', (err, stdout) => resolve({ err, stdout }));
            });
            if (stdout) {
                const lower = stdout.toLowerCase();
                for (const proc of BOOST_PROCESSES) {
                    const name = proc.toLowerCase().replace('.exe', '');
                    if (lower.includes(name)) {
                        this.detectedProcesses.push(proc);
                    }
                }
            }
        } catch (e) {}
        return this.detectedProcesses;
    }

    async performAutoControl(temp, load) {
        if (!this.autoMode || !temp) return;

        const currentProfile = powerManager.getProfile();
        let targetProfile = this.getBaseProfile(temp, load);
        const turboEnabled = currentProfile === 'performance';

        if (this.intelligentMode) {
            const { trend } = this.analyzeTempTrend(temp);
            const detectedProcesses = await this.detectBoostProcesses();

            if (detectedProcesses.length > 0 && temp < TEMP_HIGH && currentProfile !== 'performance') {
                const status = batteryManager.getStatus();
                const canBoost = !status.hasBattery || (status.isCharging && status.level >= 50);
                if (canBoost) {
                    targetProfile = 'performance';
                    console.log(`🎮 ${detectedProcesses.join(', ')} + ${temp.toFixed(1)}°C → Performance`);
                }
            }

            if (trend === 'rising-fast' && temp > 75 && turboEnabled) {
                targetProfile = 'balanced';
                console.log(`📈 Температура быстро растёт → Balanced`);
            } else if (trend === 'falling-fast' && temp < 80 && !turboEnabled) {
                targetProfile = 'performance';
                console.log(`📉 Температура быстро падает → Performance`);
            }

            if (load < IDLE_LOAD_THRESHOLD && temp > TEMP_HIGH && turboEnabled) {
                targetProfile = 'power-saver';
                console.log(`💤 Простой ${load.toFixed(1)}% + жарко ${temp.toFixed(1)}°C → Power Saver`);
            }

            if (load > HIGH_LOAD_THRESHOLD && temp > TEMP_HIGH && turboEnabled) {
                targetProfile = 'balanced';
                console.log(`🔥 Нагрузка ${load.toFixed(1)}% + ${temp.toFixed(1)}°C → Balanced`);
            }
        }

        if (targetProfile === currentProfile) return;
        if (!powerManager.canChange()) return;

        await batteryManager.updateStatus();
        const status = batteryManager.getStatus();
        const canUseBoost = !status.hasBattery || (status.isCharging && status.level >= 50);

        if (targetProfile === 'power-saver' && temp >= TEMP_THRESHOLD) {
            console.log(`🔥🔥🔥 ПЕРЕГРЕВ ${temp.toFixed(1)}°C!`);
            statsManager.incrementOverheatingPrevented();
            statsManager.saveStats();
        }

        if (!canUseBoost && targetProfile === 'performance') {
            const mode = status.isCharging ? 'зарядка' : 'отключена';
            console.log(`🔋 Батарея: ${mode}, ${status.level}% → ставим Power Saver вместо Performance`);
            await powerManager.setPowerMode('power-saver');
            return;
        }

        await powerManager.setPowerMode(targetProfile);
    }

    setAutoMode(enabled) {
        this.autoMode = enabled;
        this.saveConfig();
    }
    getAutoMode() { return this.autoMode; }

    setIntelligentMode(enabled) {
        this.intelligentMode = enabled;
        this.saveConfig();
    }
    getIntelligentMode() { return this.intelligentMode; }
}

module.exports = new AutoControl();
