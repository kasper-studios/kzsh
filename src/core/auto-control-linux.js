const powerManager = require('./power-linux');
const batteryManager = require('../core/battery-linux');
const processManager = require('../core/processes-linux');
const statsManager = require('../services/stats');
const {
    TEMP_THRESHOLD,
    TEMP_HIGH,
    TEMP_SAFE,
    IDLE_LOAD_THRESHOLD,
    IDLE_TEMP_THRESHOLD,
    HIGH_LOAD_THRESHOLD,
    TEMP_HISTORY_SIZE
} = require('../config/constants');

class AutoControl {
    constructor() {
        this.autoMode = false;
        this.intelligentMode = true;
        this.tempHistory = [];
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

    async performAutoControl(temp, load) {
        if (!this.autoMode || !temp) return;

        const turboEnabled = powerManager.getTurboState();

        if (temp >= TEMP_THRESHOLD && turboEnabled) {
            console.log(`🔥🔥🔥 ПЕРЕГРЕВ ${temp.toFixed(1)}°C! АВАРИЙНОЕ ОТКЛЮЧЕНИЕ БУСТА!`);
            statsManager.incrementOverheatingPrevented();
            statsManager.saveStats();
            await powerManager.setPowerMode(false);
            return;
        }

        if (!powerManager.canChange()) return;

        await batteryManager.updateStatus();
        if (!batteryManager.canUseBoost() && turboEnabled) {
            const status = batteryManager.getStatus();
            console.log(`🔋 Батарея: ${status.isCharging ? 'зарядка' : 'отключена'}, ${status.level}% - отключаю буст`);
            await powerManager.setPowerMode(false);
            return;
        }

        await processManager.updateProcesses();
        const detectedProcesses = processManager.getDetectedProcesses();
        const { trend } = this.analyzeTempTrend(temp);

        if (this.intelligentMode) {
            if (detectedProcesses.length > 0 && !turboEnabled && temp < TEMP_HIGH) {
                console.log(`🎮 Обнаружены процессы: ${detectedProcesses.join(', ')} - включаю буст (${temp.toFixed(1)}°C)`);
                await powerManager.setPowerMode(true);
            } else if (load < IDLE_LOAD_THRESHOLD && temp > IDLE_TEMP_THRESHOLD && turboEnabled) {
                console.log(`💤 Простой (${load.toFixed(1)}%) + жарко (${temp.toFixed(1)}°C) - отключаю буст`);
                await powerManager.setPowerMode(false);
            } else if (load >= IDLE_LOAD_THRESHOLD && temp < TEMP_SAFE && !turboEnabled) {
                console.log(`⚡ Нагрузка ${load.toFixed(1)}% + температура ${temp.toFixed(1)}°C (безопасно) - включаю буст`);
                await powerManager.setPowerMode(true);
            } else if (load > HIGH_LOAD_THRESHOLD && temp > TEMP_HIGH && turboEnabled) {
                console.log(`🔥 Высокая нагрузка ${load.toFixed(1)}% + жарко ${temp.toFixed(1)}°C - отключаю буст`);
                await powerManager.setPowerMode(false);
            }
        } else {
            if (temp < TEMP_SAFE && !turboEnabled) {
                console.log(`❄️ Температура ${temp.toFixed(1)}°C (безопасно) - включаю буст`);
                await powerManager.setPowerMode(true);
            } else if (temp > TEMP_HIGH && turboEnabled) {
                console.log(`🔥 Температура ${temp.toFixed(1)}°C (высокая) - отключаю буст`);
                await powerManager.setPowerMode(false);
            }
        }
    }

    setAutoMode(enabled) { this.autoMode = enabled; }
    getAutoMode() { return this.autoMode; }

    setIntelligentMode(enabled) { this.intelligentMode = enabled; }
    getIntelligentMode() { return this.intelligentMode; }
}

module.exports = new AutoControl();
