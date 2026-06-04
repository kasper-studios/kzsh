const temperatureReader = require('./temperature');
const powerManager = require('./power');
const batteryManager = require('./battery');
const processManager = require('./processes');
const statsManager = require('../services/stats');
const {
    TEMP_THRESHOLD,
    TEMP_HIGH,
    TEMP_SAFE,
    TEMP_MEDIUM,
    IDLE_TEMP_THRESHOLD,
    IDLE_LOAD_THRESHOLD,
    HIGH_LOAD_THRESHOLD,
    TEMP_HISTORY_SIZE
} = require('../config/constants');

class AutoControl {
    constructor() {
        this.autoMode = true;
        this.intelligentMode = true;
        this.tempHistory = [];
    }

    // Анализ тренда температуры
    analyzeTempTrend(currentTemp) {
        this.tempHistory.push(currentTemp);
        if (this.tempHistory.length > TEMP_HISTORY_SIZE) {
            this.tempHistory.shift();
        }

        if (this.tempHistory.length < 3) {
            return { trend: 'unknown', rate: 0 };
        }

        // Вычисляем скорость роста температуры
        const oldTemp = this.tempHistory[0];
        const rate = (currentTemp - oldTemp) / this.tempHistory.length;

        let trend = 'stable';
        if (rate > 1) trend = 'rising-fast';
        else if (rate > 0.5) trend = 'rising';
        else if (rate < -1) trend = 'falling-fast';
        else if (rate < -0.5) trend = 'falling';

        return { trend, rate: rate.toFixed(2) };
    }


    // Основная логика автоконтроля
    async performAutoControl(temp, load) {
        if (!this.autoMode) return;

        // КРИТИЧЕСКАЯ ЗАЩИТА — всегда срабатывает, даже на батарее (игнорирует всё)
        const turboEnabled = powerManager.getTurboState();
        if (temp >= TEMP_THRESHOLD) {
            if (turboEnabled) {
                console.log(`🔥🔥🔥 ПЕРЕГРЕВ ${temp}°C! АВАРИЙНОЕ ОТКЛЮЧЕНИЕ БУСТА!`);
                statsManager.incrementOverheatingPrevented();
                statsManager.saveStats();
                await powerManager.setPowerMode(false);
            } else {
                console.log(`🔥 КРИТИЧЕСКАЯ ТЕМПЕРАТУРА ${temp}°C! Буст выключен, ждём охлаждения...`);
            }
            return;
        }

        // Проверяем батарею
        await batteryManager.updateStatus();
        if (!batteryManager.canUseBoost()) {
            if (turboEnabled) {
                const status = batteryManager.getStatus();
                console.log(`🔋 Батарея: ${status.isCharging ? 'зарядка' : 'отключена'}, ${status.level}% - отключаю буст`);
                await powerManager.setPowerMode(false);
            }
            return;
        }

        // Анализируем тренд температуры
        const { trend, rate } = this.analyzeTempTrend(temp);

        // Обновляем процессы
        await processManager.updateProcesses();
        const detectedProcesses = processManager.getDetectedProcesses();

        // Проверяем cooldown
        const canChange = powerManager.canChange();

        console.log(`📊 ${temp.toFixed(1)}°C (${trend} ${rate}°C/цикл), ${load.toFixed(1)}%, Буст: ${turboEnabled ? 'ВКЛ' : 'ВЫКЛ'}, Cooldown: ${canChange ? 'OK' : powerManager.getTimeUntilNextChange() + 's'}`);

        // ПРЕДИКТИВНОЕ ВЫКЛЮЧЕНИЕ
        if (trend === 'rising-fast' && temp > TEMP_MEDIUM && turboEnabled) {
            console.log(`⚠️ Температура растёт быстро (${rate}°C/цикл) при ${temp}°C - превентивно отключаю буст`);
            statsManager.incrementOverheatingPrevented();
            statsManager.saveStats();
            await powerManager.setPowerMode(false);
            return;
        }

        // Интеллектуальный режим (с учетом cooldown)
        if (this.intelligentMode && canChange) {
            // Если есть важные процессы - разрешаем буст
            if (detectedProcesses.length > 0) {
                if (!turboEnabled && temp < TEMP_SAFE) {
                    console.log(`🎮 Обнаружены процессы: ${detectedProcesses.join(', ')} - включаю буст (${temp}°C)`);
                    await powerManager.setPowerMode(true);
                }
            }
            // Если простой и жарко - вырубаем буст
            else if (load < IDLE_LOAD_THRESHOLD && temp >= IDLE_TEMP_THRESHOLD && turboEnabled) {
                console.log(`💤 Простой (${load.toFixed(1)}%) + жарко (${temp}°C) - отключаю буст`);
                await powerManager.setPowerMode(false);
            }
            // Если нагрузка есть и температура БЕЗОПАСНАЯ - включаем буст
            else if (load >= IDLE_LOAD_THRESHOLD && temp < TEMP_SAFE && !turboEnabled) {
                console.log(`⚡ Нагрузка ${load.toFixed(1)}% + температура ${temp}°C (безопасно) - включаю буст`);
                await powerManager.setPowerMode(true);
            }
            // Если высокая нагрузка и температура ВЫСОКАЯ - вырубаем буст
            else if (load > HIGH_LOAD_THRESHOLD && temp >= TEMP_HIGH && turboEnabled) {
                console.log(`🔥 Высокая нагрузка ${load.toFixed(1)}% + жарко ${temp}°C - отключаю буст`);
                await powerManager.setPowerMode(false);
            }
        }

        // Базовый режим (без интеллекта, но с cooldown)
        if (!this.intelligentMode && canChange) {
            if (temp < TEMP_SAFE && !turboEnabled) {
                console.log(`❄️ Температура ${temp}°C (безопасно) - включаю буст`);
                await powerManager.setPowerMode(true);
            } else if (temp >= TEMP_HIGH && turboEnabled) {
                console.log(`🔥 Температура ${temp}°C (высокая) - отключаю буст`);
                await powerManager.setPowerMode(false);
            }
        }
    }

    setAutoMode(enabled) {
        this.autoMode = enabled;
    }

    setIntelligentMode(enabled) {
        this.intelligentMode = enabled;
    }

    getAutoMode() {
        return this.autoMode;
    }

    getIntelligentMode() {
        return this.intelligentMode;
    }
}

module.exports = new AutoControl();
