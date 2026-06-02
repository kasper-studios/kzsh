const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const { COOLDOWN } = require('../config/constants');

class PowerManager {
    constructor() {
        this.currentProfile = 'balanced';
        this.turboEnabled = false;
        this.lastBoostChange = Date.now();
        this.lastCheckedState = null;
        this.lastStateCheckTime = 0;
        this.stateCheckCacheMs = 3000;
        this.baseClockSpeed = 0;
        this.hasCheckedBaseClock = false;
    }

    async getCpuClockSpeeds() {
        try {
            let currentMHz = 0;
            let cpuCount = 0;

            try {
                const cpu0 = fs.readFileSync('/proc/cpuinfo', 'utf8');
                const blocks = cpu0.split('\n\n');
                let coreIndex = 0;
                const coreFreqs = new Set();

                for (const block of blocks) {
                    if (!block.includes('processor')) continue;
                    let modelName = '';
                    let cpuMHz = 0;
                    for (const line of block.split('\n')) {
                        if (line.startsWith('model name')) modelName = line.split(':')[1].trim();
                        if (line.startsWith('cpu MHz')) cpuMHz = parseFloat(line.split(':')[1].trim());
                    }
                    if (cpuMHz > 0) {
                        coreFreqs.add(Math.round(cpuMHz));
                        currentMHz += cpuMHz;
                        cpuCount++;
                    }
                    if (++coreIndex >= 4) break;
                }

                if (cpuCount > 0) {
                    const freqMHz = Math.round(currentMHz / cpuCount);
                    const maxMHz = coreFreqs.size > 0 ? Math.max(...coreFreqs) : freqMHz * 1.6;
                    if (!this.hasCheckedBaseClock || freqMHz < this.baseClockSpeed) {
                        this.baseClockSpeed = freqMHz;
                        this.hasCheckedBaseClock = true;
                    }
                    return { current: freqMHz, max: maxMHz, base: this.baseClockSpeed };
                }
            } catch (e) {}

            try {
                const { stdout } = await new Promise((resolve) => exec('lscpu | grep "CPU MHz"', (err, stdout) => resolve({ err, stdout })));
                if (stdout) {
                    const MHz = parseFloat(stdout.split(':')[1]?.trim() || '0');
                    if (MHz > 0) {
                        if (!this.hasCheckedBaseClock || MHz < this.baseClockSpeed) {
                            this.baseClockSpeed = MHz;
                            this.hasCheckedBaseClock = true;
                        }
                        return { current: Math.round(MHz), max: Math.round(MHz * 1.6), base: this.baseClockSpeed };
                    }
                }
            } catch (e) {}

            return { current: this.baseClockSpeed || 1800, max: (this.baseClockSpeed || 1800) * 1.6, base: this.baseClockSpeed || 1800 };
        } catch (e) {
            return { current: 1800, max: 2880, base: 1800 };
        }
    }

    async checkCurrentBoostState() {
        try {
            const raw = fs.readFileSync('/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor', 'utf8').trim();
            const gov = raw.toLowerCase();
            if (gov.includes('performance')) {
                this.currentProfile = 'performance';
                this.turboEnabled = true;
                this.lastCheckedState = true;
                this.lastStateCheckTime = Date.now();
                console.log('🔍 Буст: ВКЛ (governor: performance)');
                return true;
            }
            if (gov.includes('powersave') || gov.includes('schedutil')) {
                const haveBoost = await this.isBoostAvailable();
                if (!haveBoost) {
                    this.turboEnabled = false;
                    this.lastCheckedState = false;
                    this.lastStateCheckTime = Date.now();
                    console.log('🔍 Буст: ВЫКЛ (governor: powersave/schedutil)');
                    return false;
                }
            }
        } catch (e) {}

        const profiles = ['performance', 'balanced', 'power-saver'];
        for (const p of profiles) {
            try {
                const out = await new Promise((resolve, reject) => {
                    exec(`powerprofilesctl get ${p}`, (err, stdout) => {
                        if (err) resolve('');
                        else resolve((stdout || '').trim().toLowerCase());
                    });
                });
                if (out === p || out === 'active') {
                    this.currentProfile = p;
                    this.turboEnabled = p === 'performance';
                    this.lastCheckedState = this.turboEnabled;
                    this.lastStateCheckTime = Date.now();
                    console.log(`🔍 Буст: ${this.turboEnabled ? 'ВКЛ' : 'ВЫКЛ'} (powerprofilesctl: ${p})`);
                    return this.turboEnabled;
                }
            } catch (e) {}
        }

        this.turboEnabled = false;
        this.currentProfile = 'balanced';
        this.lastCheckedState = false;
        this.lastStateCheckTime = Date.now();
        console.log('🔍 Буст: ВЫКЛ (не удалось определить профиль)');
        return false;
    }

    async isBoostAvailable() {
        try {
            if (fs.existsSync('/sys/devices/system/cpu/cpu0/cpufreq/boost')) {
                const val = fs.readFileSync('/sys/devices/system/cpu/cpu0/cpufreq/boost', 'utf8').trim();
                return val !== '0';
            }
        } catch (e) {}
        try {
            const { stdout } = await new Promise((resolve) => exec('cpufreq-info | grep "boostable" || cpupower frequency-info | grep "boost"', (err, stdout) => resolve({ err, stdout })));
            return !(stdout || '').toLowerCase().includes('no');
        } catch (e) {
            return true;
        }
    }

    async checkBoostByClockSpeed() {
        const clocks = await this.getCpuClockSpeeds();
        const BOOST_CLOCK_THRESHOLD = Math.max(this.baseClockSpeed * 1.25, 2400);
        const isEnabled = clocks.current > BOOST_CLOCK_THRESHOLD;
        console.log(`🔍 Буст: ${isEnabled ? 'ВКЛЮЧЕН' : 'ВЫКЛЮЧЕН'} (частота: ${clocks.current} МГц, порог: ${BOOST_CLOCK_THRESHOLD} МГц)`);
        this.turboEnabled = isEnabled;
        this.lastCheckedState = isEnabled;
        this.lastStateCheckTime = Date.now();
        return isEnabled;
    }

    async getRealTurboState() {
        const now = Date.now();
        if (this.lastStateCheckTime && (now - this.lastStateCheckTime) < this.stateCheckCacheMs) {
            return this.lastCheckedState !== null ? this.lastCheckedState : this.turboEnabled;
        }
        return await this.checkBoostByClockSpeed();
    }

    getTurboState() {
        return this.turboEnabled;
    }

    async setPowerMode(profile) {
        const allowed = ['power-saver', 'balanced', 'performance'];
        if (typeof profile === 'boolean') {
            profile = profile ? 'performance' : 'power-saver';
        }
        if (!allowed.includes(profile)) profile = 'balanced';

        try {
            const out = await new Promise((resolve, reject) => {
                exec(`powerprofilesctl set ${profile}`, (err, stdout) => {
                    if (err) reject(err);
                    else resolve((stdout || '').trim());
                });
            });
        } catch (e) {
            console.error('⚠️ powerprofilesctl не удался:', e.message);
        }

        try {
            const gov = profile === 'performance' ? 'performance' : (profile === 'power-saver' ? 'powersave' : 'schedutil');
            const cpus = fs.readdirSync('/sys/devices/system/cpu/').filter(f => f.startsWith('cpu') && /^cpu\d+$/.test(f));
            for (const cpu of cpus) {
                try {
                    fs.writeFileSync(`/sys/devices/system/cpu/${cpu}/cpufreq/scaling_governor`, gov);
                } catch (e) {}
            }
        } catch (e) {
            // ignore if cannot set freq governor
        }

        const prevProfile = this.currentProfile;
        this.currentProfile = profile;
        this.turboEnabled = profile === 'performance';
        this.lastBoostChange = Date.now();
        this.lastStateCheckTime = 0;
        if (prevProfile !== profile) {
            console.log(`🔧 Режим: ${profile} (${this.turboEnabled ? 'ВКЛЮЧЕН' : 'ВЫКЛЮЧЕН'} турбо)`);
        }
        return true;
    }

    canChange() {
        return Date.now() - this.lastBoostChange > COOLDOWN;
    }

    getTimeUntilNextChange() {
        const remaining = COOLDOWN - (Date.now() - this.lastBoostChange);
        return remaining > 0 ? Math.ceil(remaining / 1000) : 0;
    }

    getProfile() {
        return this.currentProfile;
    }

    async applyOnStartup() {
        await this.checkCurrentBoostState();
        console.log(`✅ Инициализирован режим: ${this.currentProfile}`);
    }
}

module.exports = new PowerManager();
