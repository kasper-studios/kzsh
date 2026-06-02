const { exec } = require('child_process');
const { BATTERY_CHECK_INTERVAL, MIN_BATTERY_LEVEL } = require('../config/constants');

class BatteryManager {
    constructor() {
        this.status = {
            isCharging: true,
            level: 100,
            lastCheck: 0
        };
    }

    // Проверка состояния батареи
    async checkBatteryStatus() {
        return new Promise((resolve) => {
            // Get-CimInstance is more modern than Get-WmiObject
            exec('powershell -Command "Get-CimInstance Win32_Battery | Select-Object BatteryStatus, EstimatedChargeRemaining | ConvertTo-Json"', (err, stdout) => {
                if (err || !stdout) {
                    // Если не удалось проверить - считаем что на зарядке для безопасности
                    resolve({ isCharging: true, level: 100 });
                    return;
                }

                try {
                    const data = JSON.parse(stdout.trim());
                    // 2 = Charging, 1 = Discharging, 3 = Fully Charged, 4 = Low, 5 = Critical
                    // We consider everything except 1 as AC-powered for boost purposes, 
                    // or specify 2/3/6/7/8/9 as AC.
                    // Simplified: if it's 1, it's definitely battery.

                    const isCharging = data.BatteryStatus !== 1;
                    const level = data.EstimatedChargeRemaining || 100;

                    resolve({ isCharging, level });
                } catch (e) {
                    // Если парсинг не удался (например вернулся массив) - пробуем взять первый элемент
                    try {
                        const dataArray = JSON.parse(stdout.trim());
                        if (Array.isArray(dataArray) && dataArray.length > 0) {
                            const data = dataArray[0];
                            const isCharging = data.BatteryStatus !== 1;
                            const level = data.EstimatedChargeRemaining || 100;
                            resolve({ isCharging, level });
                            return;
                        }
                    } catch (e2) { }

                    resolve({ isCharging: true, level: 100 });
                }
            });
        });
    }

    // Обновление статуса батареи (с учётом интервала)
    async updateStatus() {
        const now = Date.now();
        if (now - this.status.lastCheck > BATTERY_CHECK_INTERVAL) {
            const newStatus = await this.checkBatteryStatus();
            this.status = { ...newStatus, lastCheck: now };
        }
        return this.status;
    }

    // Проверка можно ли использовать буст
    canUseBoost() {
        return this.status.isCharging && this.status.level >= MIN_BATTERY_LEVEL;
    }

    getStatus() {
        return this.status;
    }
}

module.exports = new BatteryManager();
