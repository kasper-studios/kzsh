const { HISTORY_PERIODS } = require('../config/constants');

class HistoryManager {
    constructor() {
        this.currentPeriod = '2min';
        this.history = {
            temps: [],
            loads: [],
            timestamps: [],
            turboStates: []
        };
    }

    addToHistory(temp, load, turbo) {
        const now = new Date().toLocaleTimeString('ru-RU');

        this.history.temps.push(Number(temp));
        this.history.loads.push(Number(load));
        this.history.timestamps.push(now);
        this.history.turboStates.push(Boolean(turbo));

        const maxPoints = HISTORY_PERIODS[this.currentPeriod].maxPoints;
        if (this.history.temps.length > maxPoints) {
            this.history.temps.shift();
            this.history.loads.shift();
            this.history.timestamps.shift();
            this.history.turboStates.shift();
        }
    }

    getHistory() {
        return {
            ...this.history,
            currentPeriod: this.currentPeriod
        };
    }

    setPeriod(period) {
        if (HISTORY_PERIODS[period]) {
            this.currentPeriod = period;
            this.clearHistory();
            return true;
        }
        return false;
    }

    clearHistory() {
        this.history.temps = [];
        this.history.loads = [];
        this.history.timestamps = [];
        this.history.turboStates = [];
    }

    getCurrentPeriod() {
        return this.currentPeriod;
    }
}

module.exports = new HistoryManager();
