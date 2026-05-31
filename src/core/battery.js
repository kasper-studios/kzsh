const { exec } = require('child_process');
const fs = require('fs');

class BatteryManager {
    constructor() {
        this.status = {
            isCharging: true,
            level: 100,
            lastCheck: 0
        };
    }

    checkBatteryStatus() {
        return new Promise((resolve) => {
            // Linux: используем upower
            exec('upower -i $(upower -e | grep battery) 2>/dev/null | grep -E "(state|percentage)"', (err, stdout) => {
                if (!err && stdout) {
                    const lines = stdout.trim().split('\n');
                    let isCharging = true;
                    let level = 100;

                    for (const line of lines) {
                        const lower = line.toLowerCase();
                        if (lower.includes('state:')) {
                            isCharging = !lower.includes('discharging');
                        }
                        if (lower.includes('percentage:')) {
                            const match = line.match(/([\d]+)%/);
                            if (match) level = parseInt(match[1]);
                        }
                    }

                    resolve({ isCharging, level });
                    return;
                }

                // Fallback: читаем из sysfs
                try {
                    const capacity = fs.readFileSync('/sys/class/power_supply/BAT0/capacity', 'utf8');
                    const status = fs.readFileSync('/sys/class/power_supply/BAT0/status', 'utf8');
                    
                    const level = parseInt(capacity.trim());
                    const isCharging = status.trim() !== 'Discharging';
                    
                    resolve({ isCharging, level });
                } catch (e) {
                    resolve({ isCharging: true, level: 100 });
                }
            });
        });
    }

    async updateStatus() {
        const now = Date.now();
        if (now - this.status.lastCheck > 10000) {
            const newStatus = await this.checkBatteryStatus();
            this.status = { ...newStatus, lastCheck: now };
        }
        return this.status;
    }

    canUseBoost() {
        return this.status.isCharging && this.status.level >= 50;
    }

    getStatus() {
        return this.status;
    }
}

module.exports = new BatteryManager();