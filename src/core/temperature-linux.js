const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

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
                            const temp = rawTemp / 1000;
                            if (temp > 20 && temp < 150) {
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

    async getCpuTemperature() {
        try {
            const zones = fs.readdirSync('/sys/class/thermal').filter(f => f.startsWith('thermal_zone'));
            let maxTemp = null;
            for (const zone of zones) {
                const raw = fs.readFileSync(`/sys/class/thermal/${zone}/temp`, 'utf8').trim();
                const temp = parseInt(raw, 10);
                if (!isNaN(temp) && temp > 0) {
                    const tempC = temp / 1000;
                    maxTemp = maxTemp === null ? tempC : Math.max(maxTemp, tempC);
                }
            }
            if (maxTemp !== null) {
                return maxTemp;
            }
        } catch (e) {}

        try {
            const hwmonBase = '/sys/class/hwmon';
            const hwmons = fs.readdirSync(hwmonBase);
            let maxTemp = null;
            for (const hwmon of hwmons) {
                const hwmonPath = path.join(hwmonBase, hwmon);
                const files = fs.readdirSync(hwmonPath);
                for (const file of files) {
                    if (!/^temp\d+_input$/.test(file)) continue;
                    const base = path.join(hwmonPath, file);
                    try {
                        const raw = fs.readFileSync(base, 'utf8').trim();
                        const temp = parseInt(raw, 10) / 1000;
                        if (!isNaN(temp) && temp > 0) {
                            const t = temp;
                            if (t > 20 && t < 150) {
                                maxTemp = maxTemp === null ? t : Math.max(maxTemp, t);
                            }
                        }
                    } catch (e) {
                        continue;
                    }
                }
            }
            if (maxTemp !== null) {
                return maxTemp;
            }
        } catch (e) {}

        try {
            const { stdout } = await new Promise((resolve) => {
                exec('sensors', (err, stdout) => resolve({ err, stdout }));
            });
            if (stdout) {
                const temps = [];
                const re = /\+(\d+\.?\d*)°C/g;
                let match;
                while ((match = re.exec(stdout)) !== null) {
                    temps.push(parseFloat(match[1]));
                }
                if (temps.length > 0) {
                    return Math.max(...temps);
                }
            }
        } catch (e) {}

        return null;
    }

    getLastTemp() {
        return this.lastTemp;
    }

    getMethodUsed() {
        return this.methodUsed;
    }
}

module.exports = new TemperatureReader();
