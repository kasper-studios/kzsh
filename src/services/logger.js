const fs = require('fs');
const path = require('path');
const { LOG_FILE } = require('../config/constants');

class Logger {
    constructor() {
        this.logFile = path.resolve(LOG_FILE);
        this.originalLog = console.log;
        this.originalError = console.error;
        this.isHooked = false;

        const logDir = path.dirname(this.logFile);
        if (!fs.existsSync(logDir)) {
            fs.mkdirSync(logDir, { recursive: true });
        }

        this.setupLogging();
    }

    stringifyArg(arg) {
        if (arg instanceof Error) return arg.stack || arg.message;
        if (typeof arg === 'object') {
            try { return JSON.stringify(arg); } catch (error) { return String(arg); }
        }
        return String(arg);
    }

    writeLog(message, isError = false) {
        const timestamp = new Date().toLocaleString('ru-RU');
        const text = Array.isArray(message) ? message.map((arg) => this.stringifyArg(arg)).join(' ') : String(message);
        const logMessage = `[${timestamp}] ${text}\n`;

        try {
            fs.appendFileSync(this.logFile, logMessage, 'utf8');
        } catch (error) {
            this.originalError('Ошибка записи в лог:', error.message);
        }

        if (isError) {
            this.originalError(text);
        } else {
            this.originalLog(text);
        }
    }

    setupLogging() {
        if (this.isHooked) return;
        this.isHooked = true;
        console.log = (...args) => this.writeLog(args, false);
        console.error = (...args) => this.writeLog(args, true);
    }

    info(message) { console.log(message); }
    error(message) { console.error(message); }
    warn(message) { console.log(`⚠️ ${message}`); }
    success(message) { console.log(`✅ ${message}`); }
}

module.exports = new Logger();
