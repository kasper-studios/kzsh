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
    TEMP_MEDIUM,
    COOLDOWN,
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
        this.batteryProtection = true; // авто power-saver при низком заряде
        this.tempHistory = [];
        this.lastProcessCheck = 0;
        this.detectedProcesses = [];
        this.coolingPhase = false;
        this.coolingPhaseStart = 0;
        this.configPath = path.join(__dirname, '..', '..', '.config', 'auto-mode.json');
        this.loadConfig();
    }

    loadConfig() {
        try {
            if (fs.existsSync(this.configPath)) {
                const data = JSON.parse(fs.readFileSync(this.configPath, 'utf8'));
                if (typeof data.autoMode === 'boolean') this.autoMode = data.autoMode;
                if (typeof data.intelligentMode === 'boolean') this.intelligentMode = data.intelligentMode;
                if (typeof data.batteryProtection === 'boolean') this.batteryProtection = data.batteryProtection;
            }
        } catch (e) { }
    }

    saveConfig() {
        try {
            const dir = path.dirname(this.configPath);
            if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
            fs.writeFileSync(this.configPath, JSON.stringify({
                autoMode: this.autoMode,
                intelligentMode: this.intelligentMode,
                batteryProtection: this.batteryProtection
            }, null, 2));
        } catch (e) { }
    }

    getBaseProfile(temp, load) {
        if (temp >= TEMP_HIGH) return 'power-saver';
        if (temp >= TEMP_SAFE) return 'balanced';
        if (temp < TEMP_SAFE && load > HIGH_LOAD_THRESHOLD) return 'performance';
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
        } catch (e) { }
        return this.detectedProcesses;
    }

    async performAutoControl(temp, load) {
        if (!this.autoMode || !temp) return;

        const currentProfile = powerManager.getProfile();
        const { trend, rate } = this.analyzeTempTrend(temp);

        // 1. Определение входа/продления фазы охлаждения
        const isOverheated = temp >= TEMP_HIGH;
        const isRisingFast = trend === 'rising-fast' && temp > TEMP_MEDIUM;

        if (isOverheated || isRisingFast) {
            if (!this.coolingPhase) {
                this.coolingPhase = true;
                this.coolingPhaseStart = Date.now();
                console.log(`❄️ Вход в фазу охлаждения: temp=${temp.toFixed(1)}°C, trend=${trend} (${rate}°C/с)`);
            } else {
                const now = Date.now();
                // Продлеваем таймер охлаждения, но логируем не чаще раза в 6 секунд, чтобы не спамить
                if (now - this.coolingPhaseStart > 6000) {
                    this.coolingPhaseStart = now;
                    console.log(`⏳ Продление фазы охлаждения (еще на 30с): temp=${temp.toFixed(1)}°C, trend=${trend}`);
                }
            }
        }

        let targetProfile = 'balanced';

        // 2. Логика фазы охлаждения
        if (this.coolingPhase) {
            const elapsed = Date.now() - this.coolingPhaseStart;
            const isTempSafe = temp < TEMP_SAFE;
            const isTrendSafe = trend !== 'rising-fast' && trend !== 'rising';

            if (elapsed >= COOLDOWN && isTempSafe && isTrendSafe) {
                this.coolingPhase = false;
                console.log(`✅ Выход из фазы охлаждения: temp=${temp.toFixed(1)}°C, trend=${trend}`);
                targetProfile = this.getBaseProfile(temp, load);
            } else {
                targetProfile = 'power-saver';
            }
        } else {
            // Обычный режим
            targetProfile = this.getBaseProfile(temp, load);

            if (this.intelligentMode) {
                const detectedProcesses = await this.detectBoostProcesses();

                // Буст разрешен только при безопасной температуре
                if (detectedProcesses.length > 0 && temp < TEMP_SAFE && currentProfile !== 'performance') {
                    const status = batteryManager.getStatus();
                    const canBoost = !status.hasBattery ||
                        status.isCharging ||
                        !this.batteryProtection ||
                        status.level >= 50;
                    if (canBoost) {
                        targetProfile = 'performance';
                        console.log(`🎮 ${detectedProcesses.join(', ')} + ${temp.toFixed(1)}°C → Performance`);
                    }
                }
            }
        }

        if (targetProfile === currentProfile) return;

        const isDowngrade = (p) => {
            const order = { 'performance': 2, 'balanced': 1, 'power-saver': 0 };
            return (order[p] ?? 1) < (order[currentProfile] ?? 1);
        };
        const isUpgrade = (p) => {
            const order = { 'performance': 2, 'balanced': 1, 'power-saver': 0 };
            return (order[p] ?? 1) > (order[currentProfile] ?? 1);
        };

        // Проверяем cooldown-таймеры
        if (isDowngrade(targetProfile) && !powerManager.canDowngrade(temp)) return;
        if (isUpgrade(targetProfile) && !powerManager.canUpgrade()) return;

        await batteryManager.updateStatus();
        const status = batteryManager.getStatus();

        // Блокируем performance при низком заряде если защита включена
        if (this.batteryProtection && !batteryManager.canUseBoost() && targetProfile === 'performance') {
            const mode = status.isCharging ? 'зарядка' : 'отключена';
            console.log(`🔋 Батарея: ${mode}, ${status.level}% → не даю Performance`);
            targetProfile = 'balanced';
        }

        if (targetProfile === currentProfile) return;

        if (targetProfile === 'power-saver' && temp >= TEMP_THRESHOLD) {
            console.log(`🔥🔥🔥 ПЕРЕГРЕВ ${temp.toFixed(1)}°C!`);
            statsManager.incrementOverheatingPrevented();
            statsManager.saveStats();
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

    setBatteryProtection(enabled) {
        this.batteryProtection = enabled;
        this.saveConfig();
        console.log(`🔋 Защита батареи ${enabled ? 'включена' : 'отключена'}`);
    }
    getBatteryProtection() { return this.batteryProtection; }
}

module.exports = new AutoControl();
