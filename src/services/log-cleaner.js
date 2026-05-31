const fs = require('fs');
const path = require('path');
const { LOG_DIR } = require('../config/constants');

class LogCleaner {
    constructor() {
        this.logDir = path.resolve(LOG_DIR);
        this.maxLogAge = 7 * 24 * 60 * 60 * 1000;
        this.maxLogSize = 10 * 1024 * 1024;
    }

    getLogsInfo() {
        try {
            if (!fs.existsSync(this.logDir)) {
                return { files: [], totalSize: 0, count: 0 };
            }
            const files = fs.readdirSync(this.logDir).filter(f => f.endsWith('.log'));
            let totalSize = 0;
            const logsInfo = files.map(f => {
                const filePath = path.join(this.logDir, f);
                const size = fs.statSync(filePath).size;
                totalSize += size;
                return { name: f, size };
            });
            return { files: logsInfo, totalSize, count: files.length };
        } catch (e) {
            return { files: [], totalSize: 0, count: 0 };
        }
    }

    async performCleanup() {
        return { skipped: true, reason: 'not_implemented_yet' };
    }
}

module.exports = new LogCleaner();