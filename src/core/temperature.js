const fs = require('fs').promises;
const path = require('path');
const { exec } = require('child_process');

class TemperatureReader {
    constructor() {
        this.lastTemp = 0;
    }

    async getCpuTemperature() {
        try {
            // Ищем все файлы датчиков температуры
            const hwmonPath = '/sys/class/hwmon';
            const hwmonDirs = await fs.readdir(hwmonPath);
            
            for (const dir of hwmonDirs) {
                const files = await fs.readdir(path.join(hwmonPath, dir));
                for (const file of files) {
                    if (file.startsWith('temp') && file.endsWith('_input')) {
                        const content = await fs.readFile(path.join(hwmonPath, dir, file), 'utf8');
                        const temp = parseInt(content.trim()) / 1000;
                        if (!isNaN(temp) && temp > 0 && temp < 120) {
                            this.lastTemp = temp;
                            return temp;
                        }
                    }
                }
            }
        } catch (e) {
            console.error('Ошибка чтения температуры:', e);
        }
        return this.lastTemp;
    }
}

module.exports = new TemperatureReader();
