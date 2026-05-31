const { exec } = require('child_process');

class PowerManager {
    constructor() {
        this.turboEnabled = false;  // На Linux будем отслеживать через power-profiles-daemon
        this.lastBoostChange = Date.now();
        this.hasCheckedState = false;
    }

    async getCurrentProfile() {
        return new Promise((resolve) => {
            exec('powerprofilesctl get', (err, stdout) => {
                if (err) {
                    resolve(null);
                    return;
                }
                const profile = stdout.trim();
                resolve(profile);
            });
        });
    }

    async setProfile(profile) {
        return new Promise((resolve, reject) => {
            exec(`powerprofilesctl set ${profile}`, (err, stdout, stderr) => {
                if (err) {
                    console.error(`❌ Ошибка установки профиля ${profile}:`, err.message);
                    reject(err);
                    return;
                }
                console.log(`✅ Профиль питания: ${profile}`);
                resolve(true);
            });
        });
    }

    async checkCurrentBoostState() {
        const profile = await this.getCurrentProfile();
        const isPerformance = profile === 'performance';
        this.turboEnabled = isPerformance;
        this.hasCheckedState = true;
        
        if (!this.hasCheckedState || process.env.DEBUG) {
            console.log(`🔍 Профиль: ${profile || 'unknown'} (${isPerformance ? 'performance' : 'balanced/power-saver'})`);
        }
        
        return isPerformance;
    }

    async setPowerMode(isMax) {
        const profile = isMax ? 'performance' : 'power-saver';
        
        try {
            await this.setProfile(profile);
            this.turboEnabled = isMax;
            this.lastBoostChange = Date.now();
            return true;
        } catch (err) {
            return false;
        }
    }

    async applyOnStartup() {
        await this.checkCurrentBoostState();
        return this.turboEnabled;
    }

    canChange() {
        const timeSinceLastChange = Date.now() - this.lastBoostChange;
        return timeSinceLastChange > 30000;
    }

    getTimeUntilNextChange() {
        const timeSinceLastChange = Date.now() - this.lastBoostChange;
        const remaining = 30000 - timeSinceLastChange;
        return remaining > 0 ? Math.ceil(remaining / 1000) : 0;
    }

    getTurboState() {
        return this.turboEnabled;
    }
}

module.exports = new PowerManager();