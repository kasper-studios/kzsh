const fs = require('fs').promises;
const path = require('path');
const { exec } = require('child_process');

class TemperatureReader {
    constructor() {
        this.lastTemp = 0;
        this.methodUsed = 'none';
    }

    isValidTemp(temp) {
        return Number.isFinite(temp) && temp > 0 && temp < 125;
    }

    normalizeRawTemp(raw) {
        const value = parseFloat(String(raw).trim());
        if (!Number.isFinite(value)) return null;
        const temp = value > 1000 ? value / 1000 : value;
        return this.isValidTemp(temp) ? temp : null;
    }

    async readOptional(filePath) {
        try {
            return (await fs.readFile(filePath, 'utf8')).trim();
        } catch (error) {
            return '';
        }
    }

    scoreSensor(chipName, label, fileName) {
        const text = `${chipName} ${label} ${fileName}`.toLowerCase();
        let score = 0;

        if (/(k10temp|zenpower|coretemp|cpu|processor|package|tctl|tdie|ccd|peci|x86_pkg_temp)/.test(text)) score += 100;
        if (/(cpu package|package id|tctl|tdie|core average|composite|temp1)/.test(text)) score += 30;
        if (/(nvme|amdgpu|radeon|gpu|iwlwifi|wifi|acpitz|pch|battery|bat)/.test(text)) score -= 80;

        return score;
    }

    async getTempSysfs() {
        const hwmonPath = '/sys/class/hwmon';
        const candidates = [];

        try {
            const hwmonDirs = await fs.readdir(hwmonPath);

            for (const dir of hwmonDirs) {
                const dirPath = path.join(hwmonPath, dir);
                const files = await fs.readdir(dirPath);
                const chipName = await this.readOptional(path.join(dirPath, 'name'));

                for (const file of files) {
                    if (!/^temp\d+_input$/.test(file)) continue;

                    const rawTemp = await this.readOptional(path.join(dirPath, file));
                    const temp = this.normalizeRawTemp(rawTemp);
                    if (temp === null) continue;

                    const index = file.match(/^temp(\d+)_input$/)?.[1];
                    const label = index ? await this.readOptional(path.join(dirPath, `temp${index}_label`)) : '';

                    candidates.push({
                        temp,
                        chipName,
                        label,
                        file: path.join(dirPath, file),
                        score: this.scoreSensor(chipName, label, file)
                    });
                }
            }
        } catch (error) {
            return null;
        }

        if (candidates.length === 0) return null;

        candidates.sort((a, b) => b.score - a.score);
        const best = candidates[0];
        if (best.score < 0 && candidates.length > 1) return null;

        return best.temp;
    }

    getTempSensors() {
        return new Promise((resolve) => {
            exec('sensors 2>/dev/null', { encoding: 'utf8', timeout: 2000 }, (error, stdout = '') => {
                if (error || !stdout.trim()) {
                    resolve(null);
                    return;
                }

                const cpuBlocks = stdout.split(/\n\n+/).filter((block) => {
                    const header = block.split('\n')[0]?.toLowerCase() || '';
                    return /(k10temp|zenpower|coretemp|cpu|processor)/.test(header);
                });

                const blocks = cpuBlocks.length > 0 ? cpuBlocks : stdout.split(/\n\n+/);
                const preferred = /(tctl|tdie|package id|cpu package|core average|composite)/i;
                const fallback = /(?:temp\d+|core \d+):\s*\+?([0-9]+(?:\.[0-9]+)?)°C/i;

                for (const block of blocks) {
                    for (const line of block.split('\n')) {
                        if (!preferred.test(line)) continue;
                        const match = line.match(/\+?([0-9]+(?:\.[0-9]+)?)°C/);
                        if (match) {
                            const temp = parseFloat(match[1]);
                            if (this.isValidTemp(temp)) {
                                resolve(temp);
                                return;
                            }
                        }
                    }
                }

                for (const block of blocks) {
                    for (const line of block.split('\n')) {
                        const match = line.match(fallback);
                        if (match) {
                            const temp = parseFloat(match[1]);
                            if (this.isValidTemp(temp)) {
                                resolve(temp);
                                return;
                            }
                        }
                    }
                }

                resolve(null);
            });
        });
    }

    async getCpuTemperature() {
        let temp = await this.getTempSysfs();
        if (temp !== null) {
            if (this.methodUsed !== 'sysfs') {
                console.log(`✓ Температура через Linux sysfs: ${temp.toFixed(1)}°C`);
                this.methodUsed = 'sysfs';
            }
            this.lastTemp = temp;
            return temp;
        }

        temp = await this.getTempSensors();
        if (temp !== null) {
            if (this.methodUsed !== 'sensors') {
                console.log(`✓ Температура через lm_sensors: ${temp.toFixed(1)}°C`);
                this.methodUsed = 'sensors';
            }
            this.lastTemp = temp;
            return temp;
        }

        if (this.methodUsed !== 'none') {
            console.log('⚠ Не удалось получить температуру CPU через sysfs/lm_sensors');
            this.methodUsed = 'none';
        }

        return this.lastTemp;
    }
}

module.exports = new TemperatureReader();
