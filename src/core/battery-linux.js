const fs = require('fs');
const path = require('path');

class BatteryManager {
    constructor() {
        this.status = {
            hasBattery: false,
            isCharging: true,
            level: 100,
            capacity: 100,
            status: 'unknown'
        };
    }

    checkBatteryStatus() {
        try {
            const batteryPath = '/sys/class/power_supply';
            const supplies = fs.readdirSync(batteryPath);
            let batteryFound = false;

            for (const supply of supplies) {
                if (supply.includes('BAT')) {
                    batteryFound = true;
                    try {
                        const capPath = path.join(batteryPath, supply, 'capacity');
                        const statusPath = path.join(batteryPath, supply, 'status');

                        const capacity = parseInt(fs.readFileSync(capPath, 'utf8').trim());
                        const status = fs.readFileSync(statusPath, 'utf8').trim();

                        return {
                            hasBattery: true,
                            capacity,
                            level: capacity,
                            status: status.toLowerCase(),
                            isCharging: status.toLowerCase() === 'charging'
                        };
                    } catch (e) {
                        continue;
                    }
                }
            }

            if (!batteryFound) {
                return {
                    hasBattery: false,
                    capacity: 100,
                    level: 100,
                    status: 'unknown',
                    isCharging: false
                };
            }

            return {
                hasBattery: true,
                capacity: 100,
                level: 100,
                status: 'unknown',
                isCharging: false
            };
        } catch (e) {
            return {
                hasBattery: false,
                capacity: 100,
                level: 100,
                status: 'unknown',
                isCharging: false
            };
        }
    }

    updateStatus() {
        const now = Date.now();
        const newStatus = this.checkBatteryStatus();
        this.status = { ...newStatus, lastCheck: now };
        return this.status;
    }

    canUseBoost() {
        return !this.status.hasBattery || (this.status.isCharging && this.status.level >= 50);
    }

    getStatus() {
        return this.status;
    }
}

module.exports = new BatteryManager();
