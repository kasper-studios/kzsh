const fs = require('fs');

class TemperatureReader {
    constructor() {
        this.lastTemp = 0;
        this.methodUsed = 'none';
    }
    
    // Метод для Linux: Через /sys/class/thermal
    getTempLinuxThermal() {
        return new Promise((resolve) => {
            try {
                const zones = fs.readdirSync('/sys/class/thermal').filter(f => f.startsWith('thermal_zone'));
                
                for (const zone of zones) {
                    try {
                        const tempFile = `/sys/class/thermal/${zone}/temp`;
                        const rawTemp = parseInt(fs.readFileSync(tempFile, 'utf8').trim());
                        
                        if (!isNaN(rawTemp) && rawTemp > 0) {
                            const temp = rawTemp / 1000; // Конвертируем из милли-градусов
                            if (temp > 20 && temp < 150) { // Санитарная проверка
                                this.lastTemp = temp;
                                this.methodUsed = 'linux_thermal';
                                resolve(temp);
                                return;
                            }
                        }
                    } catch (e) {
                        continue;
                    }
                }
                resolve(null);
            } catch (e) {
                resolve(null);
            }
        });
    }
    
    // Получение максимальной температуры ядер
    getTempLinuxThermalMax() {
        return new Promise((resolve) => {
            try {
                const zones = fs.readdirSync('/sys/class/thermal').filter(f => f.startsWith('thermal_zone'));
                let maxTemp = 0;
                
                for (const zone of zones) {
                    try {
                        const tempFile = `/sys/class/thermal/${zone}/temp`;
                        const rawTemp = parseInt(fs.readFileSync(tempFile, 'utf8').trim());
                        
                        if (!isNaN(rawTemp) && rawTemp > 0) {
                            const temp = rawTemp / 1000;
                            if (temp > 20 && temp < 150) {
                                maxTemp = Math.max(maxTemp, temp);
                            }
                        }
                    } catch (e) {
                        continue;
                    }
                }
                
                if (maxTemp > 0) {
                    this.lastTemp = maxTemp;
                    this.methodUsed = 'linux_thermal_max';
                    resolve(maxTemp);
                } else {
                    resolve(null);
                }
            } catch (e) {
                resolve(null);
            }
        });
    }

    // Основной метод получения температуры
    async getCpuTemperature() {
        // Пробуем максимальную температуру первой
        let temp = await this.getTempLinuxThermalMax();
        if (temp !== null) {
            return temp;
        }

        // Fallback: первая найденная температура
        temp = await this.getTempLinuxThermal();
        if (temp !== null) {
            return temp;
        }

        // Если ничего не нашли, возвращаем последнюю известную
        console.warn('⚠️ Не удалось получить температуру процессора');
        return this.lastTemp;
    }

    getLastTemp() {
        return this.lastTemp;
    }

    getMethodUsed() {
        return this.methodUsed;
    }
}

module.exports = new TemperatureReader();
