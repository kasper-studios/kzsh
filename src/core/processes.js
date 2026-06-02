const { exec } = require('child_process');
const { BOOST_PROCESSES, PROCESS_CHECK_INTERVAL } = require('../config/constants');

class ProcessManager {
    constructor() {
        this.detectedProcesses = [];
        this.lastCheck = 0;
    }

    checkBoostProcesses() {
        return new Promise((resolve) => {
            exec('ps -eo comm=,args= 2>/dev/null', { encoding: 'utf8', timeout: 3000 }, (error, stdout = '') => {
                if (error || !stdout.trim()) {
                    resolve([]);
                    return;
                }

                const lines = stdout.toLowerCase().split('\n').map((line) => line.trim()).filter(Boolean);
                const running = [];

                for (const proc of BOOST_PROCESSES) {
                    const patterns = Array.isArray(proc.patterns) ? proc.patterns : [proc];
                    const matched = lines.some((line) => patterns.some((pattern) => {
                        const normalizedPattern = String(pattern).toLowerCase();
                        return line === normalizedPattern || line.startsWith(`${normalizedPattern} `) || line.includes(normalizedPattern);
                    }));

                    if (matched) running.push(proc.name || String(proc));
                }

                resolve([...new Set(running)]);
            });
        });
    }

    async updateProcesses() {
        const now = Date.now();
        if (now - this.lastCheck > PROCESS_CHECK_INTERVAL) {
            this.detectedProcesses = await this.checkBoostProcesses();
            this.lastCheck = now;
        }
        return this.detectedProcesses;
    }

    getDetectedProcesses() {
        return this.detectedProcesses;
    }

    hasBoostProcesses() {
        return this.detectedProcesses.length > 0;
    }

    killByPatterns(processes) {
        for (const proc of processes) {
            const patterns = Array.isArray(proc.patterns) ? proc.patterns : [proc];
            for (const pattern of patterns) {
                const safePattern = String(pattern).replace(/'/g, `'\\''`);
                exec(`pkill -f '${safePattern}'`, (error) => {
                    if (!error) console.log(`  ✓ Завершён процесс по шаблону: ${pattern}`);
                });
            }
        }
    }

    killHeavyProcesses() {
        console.log('⚰️  Завершаю тяжёлые процессы для охлаждения...');
        const names = ['Google Chrome', 'Chromium', 'Firefox', 'Roblox / Wine', 'Unity Editor', 'Unreal Engine', 'OBS Studio'];
        const targets = BOOST_PROCESSES.filter((proc) => names.includes(proc.name));
        this.killByPatterns(targets);
    }

    killAllProcesses() {
        console.log('🆘 Завершаю все процессы из списка терморегулятора!');
        this.killByPatterns(BOOST_PROCESSES);
    }
}

module.exports = new ProcessManager();
