const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const { COOLDOWN } = require('../config/constants');

class PowerManager {
    constructor() {
        this.turboEnabled = true;
        this.lastBoostChange = Date.now();
        this.lastCheckedState = null;
        this.lastStateCheckTime = 0;
        this.stateCheckCacheMs = 3000;
        this.backends = null;
        this.lastBackendUsed = 'unknown';
    }

    execCommand(command, timeout = 4000) {
        return new Promise((resolve) => {
            exec(command, { encoding: 'utf8', timeout }, (error, stdout = '', stderr = '') => {
                resolve({ ok: !error, error, stdout, stderr });
            });
        });
    }

    async commandExists(command) {
        const result = await this.execCommand(`command -v ${command}`);
        return result.ok && result.stdout.trim().length > 0;
    }

    getGovernorFiles() {
        const cpuRoot = '/sys/devices/system/cpu';
        try {
            return fs.readdirSync(cpuRoot)
                .filter((entry) => /^cpu\d+$/.test(entry))
                .map((entry) => path.join(cpuRoot, entry, 'cpufreq', 'scaling_governor'))
                .filter((file) => fs.existsSync(file));
        } catch (error) {
            return [];
        }
    }

    getBoostControlFiles() {
        return [
            { file: '/sys/devices/system/cpu/cpufreq/boost', enabledValue: '1', disabledValue: '0' },
            { file: '/sys/devices/system/cpu/intel_pstate/no_turbo', enabledValue: '0', disabledValue: '1' }
        ].filter((entry) => fs.existsSync(entry.file));
    }

    async detectBackends(force = false) {
        if (this.backends && !force) return this.backends;

        const backends = [];

        if (await this.commandExists('powerprofilesctl')) {
            const result = await this.execCommand('powerprofilesctl get');
            if (result.ok) backends.push('powerprofilesctl');
        }

        if (await this.commandExists('cpupower')) {
            backends.push('cpupower');
        }

        if (this.getGovernorFiles().length > 0) {
            backends.push('sysfs-governor');
        }

        if (this.getBoostControlFiles().length > 0) {
            backends.push('sysfs-boost');
        }

        if (backends.length === 0) {
            backends.push('noop');
        }

        this.backends = backends;
        return backends;
    }

    getBackendStatus() {
        return {
            available: this.backends || [],
            lastUsed: this.lastBackendUsed,
            state: this.turboEnabled ? 'performance' : 'power-saver'
        };
    }

    async readPowerProfile() {
        if (!(await this.commandExists('powerprofilesctl'))) return null;
        const result = await this.execCommand('powerprofilesctl get');
        if (!result.ok) return null;
        return result.stdout.trim();
    }

    readBoostControls() {
        const states = [];
        for (const control of this.getBoostControlFiles()) {
            try {
                const value = fs.readFileSync(control.file, 'utf8').trim();
                states.push({
                    file: control.file,
                    value,
                    enabled: value === control.enabledValue
                });
            } catch (error) {
                // Ignore unreadable boost controls.
            }
        }
        return states;
    }

    readGovernors() {
        const governors = [];
        for (const file of this.getGovernorFiles()) {
            try {
                const governor = fs.readFileSync(file, 'utf8').trim();
                if (governor) governors.push(governor);
            } catch (error) {
                // Ignore unreadable CPU entries.
            }
        }
        return [...new Set(governors)];
    }

    async writeFileWithFallback(file, value) {
        try {
            fs.writeFileSync(file, value);
            return { ok: true, backend: 'direct-write' };
        } catch (directError) {
            const escapedFile = file.replace(/'/g, `'\\''`);
            const escapedValue = String(value).replace(/'/g, `'\\''`);
            const result = await this.execCommand(`printf '%s' '${escapedValue}' | sudo -n tee '${escapedFile}' >/dev/null`);
            return {
                ok: result.ok,
                backend: 'sudo-tee',
                error: result.error || directError,
                stderr: result.stderr
            };
        }
    }

    async applyBoostToggle(isMax) {
        const controls = this.getBoostControlFiles();
        if (controls.length === 0) return { attempted: false, ok: false };

        let okCount = 0;
        for (const control of controls) {
            const value = isMax ? control.enabledValue : control.disabledValue;
            const result = await this.writeFileWithFallback(control.file, value);
            if (result.ok) okCount++;
        }

        return { attempted: true, ok: okCount > 0, total: controls.length, changed: okCount };
    }

    async applyGovernor(isMax) {
        const governor = isMax ? 'performance' : 'powersave';
        const files = this.getGovernorFiles();
        if (files.length === 0) return { attempted: false, ok: false };

        let okCount = 0;
        for (const file of files) {
            const result = await this.writeFileWithFallback(file, governor);
            if (result.ok) okCount++;
        }

        return { attempted: true, ok: okCount > 0, total: files.length, changed: okCount };
    }

    async applyPowerProfilesCtl(isMax) {
        const profile = isMax ? 'performance' : 'power-saver';
        const result = await this.execCommand(`powerprofilesctl set ${profile}`);
        return { attempted: true, ok: result.ok, backend: 'powerprofilesctl', result };
    }

    async applyCpuPower(isMax) {
        const governor = isMax ? 'performance' : 'powersave';
        const binary = process.getuid && process.getuid() === 0 ? 'cpupower' : 'sudo -n cpupower';
        const result = await this.execCommand(`${binary} frequency-set -g ${governor}`);
        return { attempted: true, ok: result.ok, backend: 'cpupower', result };
    }

    async checkCurrentBoostState() {
        await this.detectBackends();

        const profile = await this.readPowerProfile();
        if (profile) {
            const enabled = profile === 'performance';
            this.turboEnabled = enabled;
            this.lastCheckedState = enabled;
            this.lastStateCheckTime = Date.now();
            this.lastBackendUsed = 'powerprofilesctl';
            console.log(`🔍 Linux power profile: ${profile} (${enabled ? 'турбо/производительность' : 'экономия'})`);
            return enabled;
        }

        const boostStates = this.readBoostControls();
        if (boostStates.length > 0) {
            const enabled = boostStates.some((state) => state.enabled);
            this.turboEnabled = enabled;
            this.lastCheckedState = enabled;
            this.lastStateCheckTime = Date.now();
            this.lastBackendUsed = 'sysfs-boost';
            console.log(`🔍 CPU boost sysfs: ${enabled ? 'ВКЛ' : 'ВЫКЛ'} (${boostStates.map((state) => `${path.basename(state.file)}=${state.value}`).join(', ')})`);
            return enabled;
        }

        const governors = this.readGovernors();
        if (governors.length > 0) {
            const enabled = governors.includes('performance');
            this.turboEnabled = enabled;
            this.lastCheckedState = enabled;
            this.lastStateCheckTime = Date.now();
            this.lastBackendUsed = 'sysfs-governor';
            console.log(`🔍 CPU governor: ${governors.join(', ')} (${enabled ? 'производительность' : 'экономия/баланс'})`);
            return enabled;
        }

        this.lastCheckedState = this.turboEnabled;
        this.lastStateCheckTime = Date.now();
        console.log('⚠️ Не удалось определить режим питания, доверяю внутреннему состоянию');
        return this.turboEnabled;
    }

    async getRealTurboState() {
        const now = Date.now();
        if (this.lastStateCheckTime && (now - this.lastStateCheckTime) < this.stateCheckCacheMs) {
            return this.lastCheckedState !== null ? this.lastCheckedState : this.turboEnabled;
        }
        return this.checkCurrentBoostState();
    }

    async setPowerMode(isMax) {
        await this.detectBackends();
        const modeName = isMax ? 'performance' : 'power-saver';
        console.log(`🔧 Переключаю Linux режим питания: ${modeName}`);

        const failures = [];
        let applied = false;

        if (this.backends.includes('noop')) {
            this.turboEnabled = Boolean(isMax);
            this.lastBoostChange = Date.now();
            this.lastBackendUsed = 'noop';
            console.log('⚠️ Нет доступного Linux backend питания — режим изменён только внутри приложения. Установи power-profiles-daemon/cpupower или дай права на sysfs.');
            return false;
        }

        if (this.backends.includes('powerprofilesctl')) {
            const result = await this.applyPowerProfilesCtl(isMax);
            if (result.ok) {
                applied = true;
                this.lastBackendUsed = 'powerprofilesctl';
            } else {
                failures.push(`powerprofilesctl: ${(result.result.stderr || result.result.error?.message || 'failed').trim()}`);
            }
        }

        if (!applied && this.backends.includes('cpupower')) {
            const result = await this.applyCpuPower(isMax);
            if (result.ok) {
                applied = true;
                this.lastBackendUsed = 'cpupower';
            } else {
                failures.push(`cpupower: ${(result.result.stderr || result.result.error?.message || 'failed').trim()}`);
            }
        }

        if (!applied && this.backends.includes('sysfs-governor')) {
            const result = await this.applyGovernor(isMax);
            if (result.ok) {
                applied = true;
                this.lastBackendUsed = 'sysfs-governor';
            } else {
                failures.push('sysfs-governor: write failed');
            }
        }

        // Even when another backend worked, sysfs boost toggle is useful on many AMD/Intel systems.
        const boostResult = await this.applyBoostToggle(isMax);
        if (boostResult.ok) {
            this.lastBackendUsed += '+sysfs-boost';
        }

        if (!applied && !boostResult.ok) {
            const message = failures.length > 0
                ? failures.join('; ')
                : 'нет доступных Linux backend для управления питанием';
            this.turboEnabled = Boolean(isMax);
            this.lastBoostChange = Date.now();
            this.lastBackendUsed = 'failed-fallback';
            console.error('⚠️ Не удалось переключить режим питания, но сервер продолжает работу:', message);
            return false;
        }

        this.turboEnabled = Boolean(isMax);
        this.lastBoostChange = Date.now();
        this.lastStateCheckTime = 0;
        console.log(isMax ? '✅ Производительный режим включён' : '✅ Экономичный режим включён');
        return true;
    }

    async applyOnStartup() {
        try {
            await this.setPowerMode(this.turboEnabled);
            return true;
        } catch (error) {
            console.log(`⚠️ Не удалось применить режим питания при старте: ${error.message}`);
            return false;
        }
    }

    canChange() {
        const timeSinceLastChange = Date.now() - this.lastBoostChange;
        return timeSinceLastChange > COOLDOWN;
    }

    getTimeUntilNextChange() {
        const timeSinceLastChange = Date.now() - this.lastBoostChange;
        const remaining = COOLDOWN - timeSinceLastChange;
        return remaining > 0 ? Math.ceil(remaining / 1000) : 0;
    }

    getTurboState() {
        return this.turboEnabled;
    }
}

module.exports = new PowerManager();
