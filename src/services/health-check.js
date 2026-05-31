const { exec } = require('child_process');

class HealthCheck {
    constructor() {
        this.lastCheck = 0;
        this.checkInterval = 30000;
    }

    async checkPowerProfiles() {
        return new Promise((resolve) => {
            exec('powerprofilesctl get', (err, stdout) => {
                resolve(!err && ['performance', 'power-saver', 'balanced'].includes(stdout.trim()));
            });
        });
    }

    async checkSensors() {
        return new Promise((resolve) => {
            exec('sensors 2>/dev/null | head -1', (err, stdout) => {
                resolve(!err && stdout.length > 0);
            });
        });
    }

    async performHealthCheck() {
        const now = Date.now();
        if (now - this.lastCheck < this.checkInterval) {
            return { healthy: true, cached: true };
        }
        this.lastCheck = now;

        const powerProfilesOk = await this.checkPowerProfiles();
        const sensorsOk = await this.checkSensors();

        return {
            healthy: powerProfilesOk,
            powerProfiles: powerProfilesOk,
            sensors: sensorsOk
        };
    }
}

module.exports = new HealthCheck();