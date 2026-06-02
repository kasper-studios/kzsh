const fs = require('fs');
const path = require('path');

const HISTORY_FILE = path.resolve('.logs/history.json');

const PERIOD_DURATIONS = {
    '2min': 2 * 60 * 1000,
    '5min': 5 * 60 * 1000,
    '10min': 10 * 60 * 1000,
    '1hour': 60 * 60 * 1000
};

class HistoryManager {
    constructor() {
        this.history = this.loadHistory();
        this.currentPeriod = '2min';
        this.maxPoints = 120;
    }

    loadHistory() {
        try {
            if (fs.existsSync(HISTORY_FILE)) {
                const data = JSON.parse(fs.readFileSync(HISTORY_FILE, 'utf8'));
                return {
                    timestamps: data.timestamps || [],
                    temps: data.temps || [],
                    loads: data.loads || [],
                    turboStates: data.turboStates || []
                };
            }
        } catch (e) { /* ignore */ }
        return { timestamps: [], temps: [], loads: [], turboStates: [] };
    }

    saveHistory() {
        try {
            const dir = path.dirname(HISTORY_FILE);
            if (!fs.existsSync(dir)) {
                fs.mkdirSync(dir, { recursive: true });
            }
            fs.writeFileSync(HISTORY_FILE, JSON.stringify(this.history, null, 2));
        } catch (e) { /* ignore */ }
    }

    addToHistory(temp, load, turboState) {
        this.history.timestamps.push(Date.now());
        this.history.temps.push(parseFloat(temp.toFixed(2)));
        this.history.loads.push(parseFloat(load.toFixed(1)));
        this.history.turboStates.push(turboState);

        const maxDuration = PERIOD_DURATIONS[this.currentPeriod] || PERIOD_DURATIONS['2min'];
        const cutoff = Date.now() - maxDuration;

        while (this.history.timestamps.length > 0 && this.history.timestamps[0] < cutoff) {
            this.history.timestamps.shift();
            this.history.temps.shift();
            this.history.loads.shift();
            this.history.turboStates.shift();
        }

        while (this.history.timestamps.length > this.maxPoints) {
            this.history.timestamps.shift();
            this.history.temps.shift();
            this.history.loads.shift();
            this.history.turboStates.shift();
        }

        this.saveHistory();
    }

    getHistory() {
        return {
            timestamps: this.history.timestamps,
            temps: this.history.temps,
            loads: this.history.loads,
            turboStates: this.history.turboStates,
            currentPeriod: this.currentPeriod
        };
    }

    setPeriod(period) {
        if (PERIOD_DURATIONS[period]) {
            this.currentPeriod = period;
            return true;
        }
        return false;
    }

    getCurrentPeriod() {
        return this.currentPeriod;
    }
}

module.exports = new HistoryManager();
