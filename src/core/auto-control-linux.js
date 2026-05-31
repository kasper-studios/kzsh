const powerManager = require('./power');
const {
    TEMP_THRESHOLD,
    TEMP_HIGH,
    TEMP_SAFE,
    IDLE_LOAD_THRESHOLD
} = require('../config/constants');

class AutoControl {
    constructor() {
        this.autoMode = false;
        this.tempHistory = [];
    }

    analyzeTempTrend(currentTemp) {
        this.tempHistory.push(currentTemp);
        if (this.tempHistory.length > 5) this.tempHistory.shift();
        
        if (this.tempHistory.length < 3) return { trend: 'unknown', rate: 0 };
        
        const rate = (currentTemp - this.tempHistory[0]) / this.tempHistory.length;
        let trend = 'stable';
        if (rate > 1) trend = 'rising-fast';
        else if (rate > 0.5) trend = 'rising';
        else if (rate < -1) trend = 'falling-fast';
        else if (rate < -0.5) trend = 'falling';
        
        return { trend, rate: rate.toFixed(2) };
    }

    async performAutoControl(temp, load) {
        if (!this.autoMode) return;

        const turboEnabled = powerManager.getTurboState();

        // Критический перегрев
        if (temp >= TEMP_THRESHOLD && turboEnabled) {
            console.log(`🔥 ПЕРЕГРЕВ ${temp}°C! Отключаю буст`);
            await powerManager.setPowerMode(false);
            return;
        }

        const { trend } = this.analyzeTempTrend(temp);

        if (powerManager.canChange()) {
            // Если простой и жарко - выключаем буст
            if (load < IDLE_LOAD_THRESHOLD && temp > 65 && turboEnabled) {
                console.log(`💤 Простой (${load}%) + жарко (${temp}°C) - выключаю буст`);
                await powerManager.setPowerMode(false);
            }
            // Если нагрузка и безопасно - включаем буст
            else if (load >= IDLE_LOAD_THRESHOLD && temp < TEMP_SAFE && !turboEnabled) {
                console.log(`⚡ Нагрузка ${load}% + температура ${temp}°C - включаю буст`);
                await powerManager.setPowerMode(true);
            }
        }
    }

    setAutoMode(enabled) { this.autoMode = enabled; }
    getAutoMode() { return this.autoMode; }
}

module.exports = new AutoControl();