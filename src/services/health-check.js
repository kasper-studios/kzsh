const { exec } = require('child_process');
const fs = require('fs');
const temperatureReader = require('../core/temperature');
const processManager = require('../core/processes');
const powerManager = require('../core/power');
const batteryManager = require('../core/battery');

class HealthCheck {
    constructor() {
        this.lastCheck = 0;
        this.checkInterval = 30000;
        this.lastResult = null;
    }

    execCommand(command, timeout = 3000) {
        return new Promise((resolve) => {
            exec(command, { encoding: 'utf8', timeout }, (error, stdout = '', stderr = '') => {
                resolve({ ok: !error, stdout, stderr, error });
            });
        });
    }

    async commandExists(command) {
        const result = await this.execCommand(`command -v ${command}`);
        return result.ok && result.stdout.trim().length > 0;
    }

    async checkNode() {
        const result = await this.execCommand('node -v');
        return { ok: result.ok, version: result.stdout.trim() || null };
    }

    async checkSensors() {
        const exists = await this.commandExists('sensors');
        if (!exists) return { ok: false, installed: false, optional: true };
        const result = await this.execCommand('sensors 2>/dev/null | head -5');
        return { ok: result.ok && result.stdout.trim().length > 0, installed: true, optional: true };
    }

    async checkTemperatureReader() {
        try {
            const temp = await temperatureReader.getCpuTemperature();
            return { ok: Number.isFinite(temp) && temp > 0, temperature: temp };
        } catch (error) {
            return { ok: false, error: error.message };
        }
    }

    async checkProcessDetection() {
        try {
            const processes = await processManager.checkBoostProcesses();
            return { ok: Array.isArray(processes), detected: processes };
        } catch (error) {
            return { ok: false, error: error.message };
        }
    }

    async checkBattery() {
        try {
            const status = await batteryManager.updateStatus();
            return { ok: Boolean(status), status };
        } catch (error) {
            return { ok: false, error: error.message };
        }
    }

    async checkPowerBackend() {
        try {
            const backends = await powerManager.detectBackends(true);
            const governorFiles = powerManager.getGovernorFiles();
            const boostFiles = powerManager.getBoostControlFiles();
            const sysfsCpu = fs.existsSync('/sys/devices/system/cpu');

            const realBackends = backends.filter((backend) => backend !== 'noop');
            return {
                ok: realBackends.length > 0,
                backends,
                governorFiles: governorFiles.length,
                boostFiles: boostFiles.length,
                sysfsCpu
            };
        } catch (error) {
            return { ok: false, error: error.message };
        }
    }

    async performHealthCheck() {
        const now = Date.now();
        if (this.lastResult && now - this.lastCheck < this.checkInterval) {
            return { ...this.lastResult, cached: true };
        }

        this.lastCheck = now;

        const results = {
            node: await this.checkNode(),
            temperature: await this.checkTemperatureReader(),
            processDetection: await this.checkProcessDetection(),
            powerBackend: await this.checkPowerBackend(),
            battery: await this.checkBattery(),
            sensors: await this.checkSensors(),
            timestamp: new Date().toISOString()
        };

        const critical = [];
        if (!results.node.ok) critical.push('Node.js не отвечает');
        if (!results.temperature.ok) critical.push('Не удалось получить температуру CPU');
        if (!results.processDetection.ok) critical.push('Детект процессов не работает');
        if (!results.powerBackend.ok) critical.push('Нет доступного backend для управления питанием (powerprofilesctl/cpupower/sysfs)');

        const warnings = [];
        if (!results.sensors.ok) warnings.push('lm_sensors не установлен или не отвечает (не критично, если sysfs работает)');

        const healthy = critical.length === 0;

        if (!healthy) {
            console.log('⚠️ Проблемы со здоровьем системы:');
            for (const item of critical) console.log(`  ❌ ${item}`);
            for (const item of warnings) console.log(`  ⚠️ ${item}`);
        }

        this.lastResult = {
            healthy,
            results,
            critical,
            warnings,
            timestamp: results.timestamp
        };

        return this.lastResult;
    }

    getHealthStatus() {
        return {
            lastCheck: this.lastCheck,
            lastResult: this.lastResult
        };
    }
}

module.exports = new HealthCheck();
