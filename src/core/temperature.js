const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

class TemperatureReader {
    constructor() {
        this.lastTemp = 0;
        this.methodUsed = 'none';
    }

    getTempFromSysfs() {
        try {
            const zones = fs.readdirSync('/sys/class/thermal')
                .filter(f => f.startsWith('thermal_zone'));
            
            for (const zone of zones) {
                try {
                    const tempPath = path.join('/sys/class/thermal', zone, 'temp');
                    const temp = parseInt(fs.readFileSync(tempPath, 'utf8').trim());
                    if (!isNaN(temp) && temp > 0) {
                        // sysfs returns temperature in millidegree Celsius
                        return temp / 1000;
                    }
                } catch (e) {
                    continue;
                }
            }
            return null;
        } catch (e) {
            return null;
        }
    }

    getTempFromSensors() {
        return new Promise((resolve) => {
            exec('sensors 2>/dev/null | grep -E "(Tctl|Tdie|Package id|Core|Tccd)" | head -1', (err, stdout) => {
                if (err || !stdout.trim()) {
                    resolve(null);
                    return;
                }
                const match = stdout.match(/([\d,.]+)\s*°?[Cc]/);
                if (match) {
                    const temp = parseFloat(match[1].replace(',', '.'));
                    resolve(isNaN(temp) ? null : temp);
                } else {
                    resolve(null);
                }
            });
        });
    }

    async getCpuTemperature() {
        // Метод 1: Через /sys/class/thermal (нативно, быстро)
        let temp = this.getTempFromSysfs();
        if (temp !== null && temp > 0) {
            if (this.methodUsed !== 'sysfs') {
                console.log(`✓ Температура через sysfs: ${temp}°C`);
                this.methodUsed = 'sysfs';
            }
            this.lastTemp = temp;
            return temp;
        }

        // Метод 2: Через sensors (нужен пакет lm_sensors)
        temp = await this.getTempFromSensors();
        if (temp !== null && temp > 0) {
            if (this.methodUsed !== 'sensors') {
                console.log(`✓ Температура через sensors: ${temp}°C`);
                this.methodUsed = 'sensors';
            }
            this.lastTemp = temp;
            return temp;
        }

        if (this.methodUsed !== 'none') {
            console.log('⚠ Не удалось получить температуру');
            this.methodUsed = 'none';
        }

        return this.lastTemp;
    }
}

module.exports = new TemperatureReader();