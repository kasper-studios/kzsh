const os = require('os');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

class HealthCheck {
    constructor() {
        this.tempReader = require('../core/temperature-linux');
        this.powerManager = require('../core/power-linux');
        this.issues = [];
    }

    async performHealthCheck() {
        this.issues = [];
        try {
            await this.checkCpuLoad();
            await this.checkMemory();
            await this.checkDisk();
            await this.checkTemperatureSource();
            await this.checkPowerProfiles();
            await this.checkGovernor();
        } catch (e) {
            this.issues.push({ component: 'health', message: e.message });
        }

        const healthy = this.issues.length === 0;
        if (!healthy) {
            console.log('⚠️ Проблемы здоровья системы:');
            for (const issue of this.issues) {
                console.log(`  ❌ ${issue.component}: ${issue.message}`);
            }
        }
        return { healthy, issues: this.issues };
    }

    async checkCpuLoad() {
        const load = await new Promise((resolve) => {
            os.cpuUsage((v) => resolve(v * 100));
        });
        if (load > 95) {
            this.issues.push({ component: 'cpu', message: `Нагрузка ${load.toFixed(1)}%` });
        }
    }

    async checkMemory() {
        const total = os.totalmem();
        const free = os.freemem();
        const used = total - free;
        const percent = (used / total) * 100;
        if (percent > 95) {
            this.issues.push({ component: 'memory', message: `Память заполнена на ${percent.toFixed(1)}%` });
        }
    }

    async checkDisk() {
        try {
            const { stdout } = await new Promise((resolve) => exec("df -h / | awk 'NR==2{print $5}'", (err, stdout) => resolve({ err, stdout })));
            if (stdout) {
                const usage = parseInt(stdout.trim());
                if (usage > 95) {
                    this.issues.push({ component: 'disk', message: `Диск заполнен на ${usage}%` });
                }
            }
        } catch (e) {}
    }

    async checkTemperatureSource() {
        const temp = await this.tempReader.getCpuTemperature();
        if (temp === null || temp <= 0) {
            this.issues.push({ component: 'temperature', message: 'Не удалось получить температуру CPU' });
        }
    }

    async checkPowerProfiles() {
        try {
            const { stdout } = await new Promise((resolve) => exec('powerprofilesctl list', (err, stdout) => resolve({ err, stdout })));
            if (!stdout || !stdout.includes('performance')) {
                this.issues.push({ component: 'power', message: 'powerprofilesctl не поддерживает performance профиль' });
            }
        } catch (e) {
            this.issues.push({ component: 'power', message: 'powerprofilesctl не найден' });
        }
    }

    async checkGovernor() {
        try {
            const govPath = '/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor';
            if (fs.existsSync(govPath)) {
                const gov = fs.readFileSync(govPath, 'utf8').trim();
                console.log(`🔍 CPU governor: ${gov}`);
            }
        } catch (e) {}
    }
}

module.exports = new HealthCheck();
