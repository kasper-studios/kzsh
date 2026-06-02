const { exec } = require('child_process');
const { PROCESS_CHECK_INTERVAL, BOOST_PROCESSES } = require('../config/constants');

class ProcessManager {
    constructor() {
        this.detectedProcesses = [];
        this.lastCheck = 0;
    }

    async checkBoostProcesses() {
        return new Promise((resolve) => {
            exec('ps aux', (err, stdout) => {
                if (err || !stdout) {
                    resolve([]);
                    return;
                }

                const running = [];
                const lowerOutput = stdout.toLowerCase();

                for (const proc of BOOST_PROCESSES) {
                    const procName = proc.toLowerCase().replace('.exe', '');
                    if (lowerOutput.includes(procName)) {
                        running.push(proc);
                    }
                }

                resolve(running);
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
}

module.exports = new ProcessManager();
