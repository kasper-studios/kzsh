const { exec } = require('child_process');

class PowerManager {
    constructor() {
        this.turboEnabled = true;
    }

    async setPowerMode(isMax) {
        return new Promise((resolve, reject) => {
            const governor = isMax ? 'performance' : 'powersave';
            const cmd = `echo ${governor} | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`;
            
            exec(cmd, (err) => {
                if (err) {
                    console.error('Ошибка установки режима питания:', err);
                    reject(err);
                } else {
                    this.turboEnabled = isMax;
                    console.log(`Режим питания установлен на: ${governor}`);
                    resolve();
                }
            });
        });
    }

    getTurboState() {
        return this.turboEnabled;
    }
}

module.exports = new PowerManager();
