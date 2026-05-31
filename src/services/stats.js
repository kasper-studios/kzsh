const fs = require('fs');
const path = require('path');
const { STATS_FILE } = require('../config/constants');

class StatsManager {
    constructor() {
        this.statsFile = path.resolve(STATS_FILE);
        this.sessionStart = Date.now();

        this.stats = {
            owner: '@kasperenok',
            totalSessions: 0,
            overheatingPrevented: 0,
            totalRuntime: 0,
            longestSession: 0,
            maxTemperature: 0,
            avgTemperature: 0,
            tempSum: 0,
            tempCount: 0,
            firstStart: null,
            lastStart: null
        };

        this.loadStats();
        this.startSession();
    }

    loadStats() {
        if (fs.existsSync(this.statsFile)) {
            try {
                const data = fs.readFileSync(this.statsFile, 'utf8');
                this.stats = { ...this.stats, ...JSON.parse(data) };
                console.log('📊 Статистика загружена');
            } catch (e) {}
        }
    }

    startSession() {
        this.stats.totalSessions++;
        this.stats.lastStart = new Date().toISOString();
        if (!this.stats.firstStart) {
            this.stats.firstStart = this.stats.lastStart;
        }
    }

    saveStats() {
        try {
            const dir = path.dirname(this.statsFile);
            if (!fs.existsSync(dir)) {
                fs.mkdirSync(dir, { recursive: true });
            }
            fs.writeFileSync(this.statsFile, JSON.stringify(this.stats, null, 2));
        } catch (e) {}
    }

    updateTempStats(temp) {
        this.stats.tempSum += temp;
        this.stats.tempCount++;
        this.stats.avgTemperature = this.stats.tempSum / this.stats.tempCount;

        if (temp > this.stats.maxTemperature) {
            this.stats.maxTemperature = temp;
        }
    }

    incrementOverheatingPrevented() {
        this.stats.overheatingPrevented++;
    }

    updateRuntime(seconds) {
        this.stats.totalRuntime += seconds;
        const currentSessionTime = Math.floor((Date.now() - this.sessionStart) / 1000);
        if (currentSessionTime > this.stats.longestSession) {
            this.stats.longestSession = currentSessionTime;
        }
    }

    getStats() {
        return {
            ...this.stats,
            currentSessionTime: Math.floor((Date.now() - this.sessionStart) / 1000)
        };
    }

    formatTime(seconds) {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        if (hours > 0) return `${hours}ч ${minutes}м`;
        return `${minutes}м`;
    }

    printStats() {
        console.log(`\n📊 СТАТИСТИКА:`);
        console.log(`   • Всего сессий: ${this.stats.totalSessions}`);
        console.log(`   • Спасено от перегрева: ${this.stats.overheatingPrevented} раз`);
        console.log(`   • Средняя температура: ${this.stats.avgTemperature.toFixed(1)}°C`);
        console.log(`   • Самая высокая температура: ${this.stats.maxTemperature.toFixed(1)}°C`);
        console.log(`   • Общее время работы: ${this.formatTime(this.stats.totalRuntime)}`);
        console.log(`   • Самая длинная сессия: ${this.formatTime(this.stats.longestSession)}\n`);
    }

    endSession() {
        const currentSessionTime = Math.floor((Date.now() - this.sessionStart) / 1000);
        this.stats.totalRuntime += currentSessionTime;
        if (currentSessionTime > this.stats.longestSession) {
            this.stats.longestSession = currentSessionTime;
        }
        this.saveStats();
    }
}

module.exports = new StatsManager();