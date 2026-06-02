const fs = require('fs');
const path = require('path');
const { LOG_DIR, MAX_LOG_AGE, MAX_LOG_SIZE } = require('../config/constants');

class LogCleaner {
    constructor() {
        this.logDir = path.resolve(LOG_DIR);
        this.maxLogAge = MAX_LOG_AGE;
        this.maxLogSize = MAX_LOG_SIZE;
        this.cleanInterval = 24 * 60 * 60 * 1000;
        this.lastClean = 0;
    }

    getFileSize(filePath) {
        try {
            return fs.statSync(filePath).size;
        } catch (error) {
            return 0;
        }
    }

    getFileAge(filePath) {
        try {
            return Date.now() - fs.statSync(filePath).mtime.getTime();
        } catch (error) {
            return 0;
        }
    }

    rotateLog(logFile) {
        try {
            const date = new Date().toISOString().split('T')[0];
            const ext = path.extname(logFile);
            const base = path.basename(logFile, ext);
            const dir = path.dirname(logFile);

            let counter = 1;
            let newName = path.join(dir, `${base}-${date}${ext}`);
            while (fs.existsSync(newName)) {
                newName = path.join(dir, `${base}-${date}-${counter}${ext}`);
                counter++;
            }

            fs.renameSync(logFile, newName);
            console.log(`📦 Лог заархивирован: ${path.basename(newName)}`);
            return newName;
        } catch (error) {
            console.error('❌ Ошибка ротации лога:', error.message);
            return null;
        }
    }

    deleteOldLogs() {
        try {
            if (!fs.existsSync(this.logDir)) return { deleted: 0, size: 0 };

            const files = fs.readdirSync(this.logDir);
            let deleted = 0;
            let freedSize = 0;

            for (const file of files) {
                if (file === 'termoregulator.log' || file === 'stats.json') continue;

                const filePath = path.join(this.logDir, file);
                if (!fs.statSync(filePath).isFile()) continue;

                const age = this.getFileAge(filePath);
                if (age > this.maxLogAge) {
                    const size = this.getFileSize(filePath);
                    fs.unlinkSync(filePath);
                    deleted++;
                    freedSize += size;
                    console.log(`🗑️ Удалён старый лог: ${file} (${(size / 1024).toFixed(1)} KB)`);
                }
            }

            return { deleted, size: freedSize };
        } catch (error) {
            console.error('❌ Ошибка удаления старых логов:', error.message);
            return { deleted: 0, size: 0 };
        }
    }

    checkCurrentLog() {
        const logFile = path.join(this.logDir, 'termoregulator.log');
        if (!fs.existsSync(logFile)) return { rotated: false, reason: 'not_exists' };

        const size = this.getFileSize(logFile);
        if (size > this.maxLogSize) {
            this.rotateLog(logFile);
            return { rotated: true, reason: 'size', size };
        }

        return { rotated: false, size };
    }

    async performCleanup() {
        const now = Date.now();
        if (now - this.lastClean < this.cleanInterval) {
            return { skipped: true, reason: 'too_soon' };
        }

        this.lastClean = now;
        console.log('🧹 Запуск очистки логов...');

        const rotateResult = this.checkCurrentLog();
        const deleteResult = this.deleteOldLogs();

        if (deleteResult.deleted > 0) {
            console.log(`✅ Очистка завершена: удалено ${deleteResult.deleted} файлов, освобождено ${(deleteResult.size / 1024 / 1024).toFixed(2)} MB`);
        } else {
            console.log('✅ Очистка завершена: старых логов не найдено');
        }

        return {
            rotated: rotateResult.rotated,
            deleted: deleteResult.deleted,
            freedSize: deleteResult.size,
            timestamp: new Date().toISOString()
        };
    }

    forceCleanup() {
        this.lastClean = 0;
        return this.performCleanup();
    }

    getLogsInfo() {
        try {
            if (!fs.existsSync(this.logDir)) return { files: [], totalSize: 0, count: 0 };

            const files = fs.readdirSync(this.logDir);
            const logsInfo = [];
            let totalSize = 0;

            for (const file of files) {
                if (!file.endsWith('.log')) continue;

                const filePath = path.join(this.logDir, file);
                const size = this.getFileSize(filePath);
                const age = this.getFileAge(filePath);

                logsInfo.push({ name: file, size, age, path: filePath });
                totalSize += size;
            }

            return { files: logsInfo, totalSize, count: logsInfo.length };
        } catch (error) {
            console.error('❌ Ошибка получения информации о логах:', error.message);
            return { files: [], totalSize: 0, count: 0 };
        }
    }
}

module.exports = new LogCleaner();
