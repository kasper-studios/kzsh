const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const { BATTERY_CHECK_INTERVAL, MIN_BATTERY_LEVEL } = require('../config/constants');

class BatteryManager {
    constructor() {
        this.status = {
            isCharging: true,
            level: 100,
            lastCheck: 0,
            source: 'default-ac',
            hasBattery: false
        };
    }

    parseUpowerOutput(stdout) {
        const devices = stdout.split(/\n(?=\s*native-path:|\s*vendor:|\s*model:)/).filter(Boolean);
        const blocks = devices.length > 0 ? devices : [stdout];

        for (const block of blocks) {
            const lower = block.toLowerCase();
            if (!/(battery|percentage|state)/.test(lower)) continue;

            const stateMatch = block.match(/state:\s*([^\n]+)/i);
            const percentMatch = block.match(/percentage:\s*([0-9]+(?:\.[0-9]+)?)%/i);
            if (!percentMatch && !stateMatch) continue;

            const state = stateMatch ? stateMatch[1].trim().toLowerCase() : 'unknown';
            const level = percentMatch ? Math.round(parseFloat(percentMatch[1])) : 100;
            const isCharging = !['discharging', 'empty'].includes(state);

            return { isCharging, level, source: 'upower', hasBattery: true };
        }

        return null;
    }

    checkUpower() {
        return new Promise((resolve) => {
            const cmd = 'upower -i $(upower -e 2>/dev/null | grep -i battery | head -1) 2>/dev/null';
            exec(cmd, { encoding: 'utf8', timeout: 2500 }, (error, stdout = '') => {
                if (error || !stdout.trim()) {
                    resolve(null);
                    return;
                }
                resolve(this.parseUpowerOutput(stdout));
            });
        });
    }

    checkSysfs() {
        const powerRoot = '/sys/class/power_supply';
        try {
            const devices = fs.readdirSync(powerRoot).filter((entry) => {
                const typePath = path.join(powerRoot, entry, 'type');
                const type = fs.existsSync(typePath) ? fs.readFileSync(typePath, 'utf8').trim().toLowerCase() : '';
                return type === 'battery' || /^bat/i.test(entry);
            });

            if (devices.length === 0) return null;

            for (const device of devices) {
                const devicePath = path.join(powerRoot, device);
                const capacityPath = path.join(devicePath, 'capacity');
                const statusPath = path.join(devicePath, 'status');

                const level = fs.existsSync(capacityPath)
                    ? parseInt(fs.readFileSync(capacityPath, 'utf8').trim(), 10)
                    : 100;

                const status = fs.existsSync(statusPath)
                    ? fs.readFileSync(statusPath, 'utf8').trim().toLowerCase()
                    : 'unknown';

                if (!Number.isNaN(level)) {
                    return {
                        isCharging: !['discharging', 'empty'].includes(status),
                        level,
                        source: `sysfs:${device}`,
                        hasBattery: true
                    };
                }
            }
        } catch (error) {
            return null;
        }

        return null;
    }

    async checkBatteryStatus() {
        const upower = await this.checkUpower();
        if (upower) return upower;

        const sysfs = this.checkSysfs();
        if (sysfs) return sysfs;

        // Desktop PCs often have no battery. Treat as AC-powered.
        return { isCharging: true, level: 100, source: 'no-battery-ac', hasBattery: false };
    }

    async updateStatus() {
        const now = Date.now();
        if (now - this.status.lastCheck > BATTERY_CHECK_INTERVAL) {
            const newStatus = await this.checkBatteryStatus();
            this.status = { ...newStatus, lastCheck: now };
        }
        return this.status;
    }

    canUseBoost() {
        return this.status.isCharging && this.status.level >= MIN_BATTERY_LEVEL;
    }

    getStatus() {
        return this.status;
    }
}

module.exports = new BatteryManager();
