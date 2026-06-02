const express = require('express');
const os = require('os-utils');
const temperatureReader = require('../core/temperature-linux');
const powerManager = require('../core/power-linux');
const batteryManager = require('../core/battery-linux');
const processManager = require('../core/processes-linux');
const autoControl = require('../core/auto-control-linux');
const statsManager = require('../services/stats');
const historyManager = require('../services/history');
const healthCheck = require('../services/health-check-linux');
const logCleaner = require('../services/log-cleaner');

const router = express.Router();

// Получение нагрузки CPU
const getCpuLoad = () => {
    return new Promise((resolve) => {
        os.cpuUsage((v) => {
            resolve(v * 100);
        });
    });
};

// Получение статуса
router.get('/status', async (req, res) => {
    try {
        const temperature = await temperatureReader.getCpuTemperature();
        const load = await getCpuLoad();
        
        // Обновляем статистику температуры
        statsManager.updateTempStats(temperature);

        // Обновляем историю
        historyManager.addToHistory(temperature, load, powerManager.getTurboState());

        // Обновляем статус батареи перед отправкой
        await batteryManager.updateStatus();
        
        res.json({
            temperature: temperature,
            load: load.toFixed(1),
            turboEnabled: powerManager.getTurboState(),
            autoMode: autoControl.getAutoMode(),
            intelligentMode: autoControl.getIntelligentMode(),
            detectedProcesses: processManager.getDetectedProcesses(),
            saveCount: statsManager.getStats().overheatingPrevented,
            battery: batteryManager.getStatus(),
            stats: statsManager.getStats()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Получение истории для графика
router.get('/history', (req, res) => {
    const period = req.query.period || historyManager.getCurrentPeriod();
    res.json({
        ...historyManager.getHistory(),
        currentPeriod: period
    });
});

// Изменение периода истории
router.post('/history/period', (req, res) => {
    const newPeriod = req.body.period;
    if (historyManager.setPeriod(newPeriod)) {
        res.json({ success: true, period: newPeriod });
    } else {
        res.status(400).json({ error: 'Invalid period' });
    }
});

// Ручное управление турбо
router.post('/turbo', async (req, res) => {
    try {
        const { enabled } = req.body;
        await powerManager.setPowerMode(enabled);
        res.json({ success: true, turboEnabled: powerManager.getTurboState() });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Переключение автоматического режима
router.post('/auto', (req, res) => {
    autoControl.setAutoMode(req.body.enabled);
    res.json({ success: true, autoMode: autoControl.getAutoMode() });
});

// Переключение интеллектуального режима
router.post('/intelligent', (req, res) => {
    autoControl.setIntelligentMode(req.body.enabled);
    res.json({ success: true, intelligentMode: autoControl.getIntelligentMode() });
});

// Проверка здоровья системы
router.get('/health', async (req, res) => {
    try {
        const health = await healthCheck.performHealthCheck();
        res.json(health);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Информация о логах
router.get('/logs/info', (req, res) => {
    try {
        const info = logCleaner.getLogsInfo();
        res.json(info);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Принудительная очистка логов
router.post('/logs/cleanup', async (req, res) => {
    try {
        const result = await logCleaner.forceCleanup();
        res.json({ success: true, result });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;
