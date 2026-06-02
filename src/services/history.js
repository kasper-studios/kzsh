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
    
    // Добавление в историю
    addToHistory(temp, load, turbo) {
        const now = new Date().toLocaleTimeString('ru-RU');
        
        this.history.temps.push(temp);
        this.history.loads.push(load);
        this.history.timestamps.push(now);
        this.history.turboStates.push(turbo);
        
        // Храним только нужное количество точек для текущего периода
        const maxPoints = HISTORY_PERIODS[this.currentPeriod].maxPoints;
        if (this.history.temps.length > maxPoints) {
            this.history.temps.shift();
            this.history.loads.shift();
            this.history.timestamps.shift();
            this.history.turboStates.shift();
        }
    }
    
    // Получение истории
    getHistory() {
        return {
            ...this.history,
            currentPeriod: this.currentPeriod
        };
    }
    
    // Изменение периода
    setPeriod(period) {
        if (HISTORY_PERIODS[period]) {
            this.currentPeriod = period;
            // Очищаем историю при смене периода
            this.clearHistory();
            return true;
        }
        return false;
    }
    
    // Очистка истории
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
