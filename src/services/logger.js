const fs = require('fs');
const path = require('path');
const { LOG_FILE, LOG_DIR } = require('../config/constants');

class Logger {
    constructor() {
        this.logFile = path.resolve(LOG_FILE);
        this.originalLog = console.log;
        this.originalError = console.error;
        
        // Создаём директорию для логов если её нет
        const logDir = path.dirname(this.logFile);
        if (!fs.existsSync(logDir)) {
            fs.mkdirSync(logDir, { recursive: true });
        }
        
        this.setupLogging();
    }
    
    writeLog(message, isError = false) {
        const timestamp = new Date().toLocaleString('ru-RU');
        const logMessage = `[${timestamp}] ${message}\n`;
        
        // Пишем в файл
        try {
            fs.appendFileSync(this.logFile, logMessage, 'utf8');
        } catch (e) {
            this.originalError('Ошибка записи в лог:', e.message);
        }
        
        // Выводим в консоль
        if (isError) {
            this.originalError(message);
        } else {
            this.originalLog(message);
        }
    }
    
    setupLogging() {
        // Переопределяем console.log и console.error
        console.log = (...args) => this.writeLog(args.join(' '));
        console.error = (...args) => this.writeLog(args.join(' '), true);
    }
    
    info(message) {
        console.log(message);
    }
    
    error(message) {
        console.error(message);
    }
    
    warn(message) {
        console.log(`⚠️ ${message}`);
    }
    
    success(message) {
        console.log(`✅ ${message}`);
    }
}

module.exports = new Logger();
