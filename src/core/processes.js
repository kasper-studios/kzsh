const { exec } = require('child_process');

class ProcessManager {
    constructor() {
        this.detectedProcesses = [];
        this.lastCheck = 0;
    }

    checkBoostProcesses() {
        return new Promise((resolve) => {
            // Linux: используем ps aux
            exec('ps aux --no-headers -o comm= 2>/dev/null', (err, stdout) => {
                if (err || !stdout) {
                    resolve([]);
                    return;
                }

                const running = [];
                const lines = stdout.toLowerCase().trim().split('\n');
                const runningProcs = new Set(lines.map(l => l.trim()));

                // Linux аналоги windows процессов
                const boostPatterns = [
                    'java',           // Minecraft
                    'code',           // VS Code
                    'steam',
                    'lutris',
                    'heroic',
                    'chromium',
                    'chrome',
                    'firefox',
                    'obs',
                    'unity',
                    'unreal'
                ];

                for (const proc of boostPatterns) {
                    if (runningProcs.has(proc)) {
                        running.push(proc);
                    }
                }

                resolve(running);
            });
        });
    }

    async updateProcesses() {
        const now = Date.now();
        if (now - this.lastCheck > 5000) {
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
}

module.exports = new ProcessManager();