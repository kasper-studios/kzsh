const { exec } = require('child_process');
const { COOLDOWN } = require('../config/constants');
const fs = require('fs');

class PowerManager {
    constructor() {
        this.turboEnabled = true; // Считаем что буст включен по умолчанию
        this.lastBoostChange = Date.now();
        this.currentProfile = 'balanced';
    }

    // Получить текущий профиль питания
    async getCurrentProfile() {
        return new Promise((resolve) => {
            exec('powerprofilesctl get', (err, stdout) => {
                if (err) {
                    resolve(this.currentProfile);
                    return;
                }
                const profile = stdout.trim();
                this.currentProfile = profile;
                resolve(profile);
            });
        });
    }

    // Установить режим питания: true = performance (со свопом CPU), false = power-saver
    async setPowerMode(isMax) {
        return new Promise((resolve) => {
            const profile = isMax ? 'performance' : 'power-saver';
            
            exec(`powerprofilesctl set ${profile}`, (err) => {
                if (err) {
                    console.warn(`⚠️ Не удалось установить профиль ${profile}`);
                    resolve(false);
                    return;
                }
                
                this.turboEnabled = isMax;
                this.lastBoostChange = Date.now();
                this.currentProfile = profile;
                console.log(`✅ Режим питания: ${profile.toUpperCase()}`);
                resolve(true);
            });
        });
    }

    // Проверка текущего режима буста
    async checkCurrentBoostState() {
        return new Promise((resolve) => {
            exec('powerprofilesctl get', (err, stdout) => {
                if (err) {
                    console.warn('⚠️ Не удалось проверить режим питания');
                    resolve(this.turboEnabled);
                    return;
                }
                
                const profile = stdout.trim().toLowerCase();
                const isPerformance = profile === 'performance';
                
                this.turboEnabled = isPerformance;
                this.currentProfile = profile;
                
                console.log(`🔍 Режим питания: ${profile} (буст: ${isPerformance ? 'ВКЛЮЧЕН' : 'ВЫКЛЮЧЕН'})`);
                resolve(isPerformance);
            });
        });
    }

    // Получение информации о CPU из /proc/cpuinfo
    getCpuInfo() {
        return new Promise((resolve) => {
            try {
                const cpuinfo = fs.readFileSync('/proc/cpuinfo', 'utf8');
                const lines = cpuinfo.split('\n');
                const info = {};
                
                for (const line of lines) {
                    if (line.includes('model name')) {
                        info.modelName = line.split(':')[1].trim();
                    }
                    if (line.includes('cpu MHz')) {
                        if (!info.mhz) info.mhz = [];
                        info.mhz.push(parseFloat(line.split(':')[1].trim()));
                    }
                }
                
                if (info.mhz && info.mhz.length > 0) {
                    info.currentMhz = Math.max(...info.mhz);
                }
                
                resolve(info);
            } catch (e) {
                resolve({});
            }
        });
    }

    // Проверка возможности переключения
    canChange() {
        return Date.now() - this.lastBoostChange > COOLDOWN;
    }

    getTurboState() {
        return this.turboEnabled;
    }

    // Применение режима при старте
    async applyOnStartup() {
        await this.checkCurrentBoostState();
        console.log(`✅ Инициализирован режим: ${this.currentProfile}`);
    }
}

module.exports = new PowerManager();
