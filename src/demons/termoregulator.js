const os = require('os-utils');

require('../services/logger');

const temperatureReader = require('../core/temperature');
const powerManager = require('../core/power');
const autoControl = require('../core/auto-control');
const statsManager = require('../services/stats');
const healthCheck = require('../services/health-check');
const logCleaner = require('../services/log-cleaner');
const {
    AUTO_CONTROL_INTERVAL,
    STATS_SAVE_INTERVAL,
    HEALTH_CHECK_INTERVAL,
    LOG_CLEANUP_INTERVAL,
    TEMP_THRESHOLD
} = require('../config/constants');

const getCpuLoad = () => new Promise((resolve) => {
    os.cpuUsage((value) => resolve(value * 100));
});

async function safeRun(label, fn) {
    try {
        return await fn();
    } catch (error) {
        console.error(`❌ ${label}:`, error.message || error);
        return null;
    }
}

async function startup() {
    console.log('\n════════════════════════════════════════════════');
    console.log('  🌡️ KZSH ТЕРМОРЕГУЛЯТОР DAEMON (Linux)');
    console.log('════════════════════════════════════════════════\n');

    await safeRun('Проверка режима питания', () => powerManager.checkCurrentBoostState());
    await safeRun('Применение режима питания при старте', () => powerManager.applyOnStartup());

    statsManager.printStats();

    console.log('🔍 Проверка здоровья системы...');
    const health = await safeRun('Проверка здоровья системы', () => healthCheck.performHealthCheck());
    if (health?.healthy) {
        console.log('✅ Все системы работают нормально\n');
    } else {
        console.log('⚠️ Обнаружены проблемы, но демон продолжает работу\n');
    }

    const logsInfo = logCleaner.getLogsInfo();
    if (logsInfo.totalSize > 5 * 1024 * 1024) {
        console.log(`📦 Логи занимают ${(logsInfo.totalSize / 1024 / 1024).toFixed(2)} MB, запускаю очистку...`);
        await safeRun('Очистка логов', () => logCleaner.performCleanup());
    }

    const temp = await safeRun('Проверка температуры при старте', () => temperatureReader.getCpuTemperature());
    if (typeof temp === 'number' && temp >= TEMP_THRESHOLD && powerManager.getTurboState()) {
        console.log(`🔥🔥🔥 ВНИМАНИЕ! Температура ${temp.toFixed(1)}°C при запуске! Отключаю турбо...`);
        await safeRun('Аварийное отключение турбо', () => powerManager.setPowerMode(false));
    }
}

setInterval(async () => {
    await safeRun('Ошибка автоконтроля daemon', async () => {
        const temp = await temperatureReader.getCpuTemperature();
        const load = await getCpuLoad();
        await autoControl.performAutoControl(temp, load);
    });
}, AUTO_CONTROL_INTERVAL);

setInterval(() => {
    statsManager.updateRuntime(30);
    statsManager.saveStats();
}, STATS_SAVE_INTERVAL);

setInterval(() => {
    safeRun('Ошибка проверки здоровья daemon', () => healthCheck.performHealthCheck());
}, HEALTH_CHECK_INTERVAL);

setInterval(() => {
    safeRun('Ошибка очистки логов daemon', () => logCleaner.performCleanup());
}, LOG_CLEANUP_INTERVAL);

process.on('SIGINT', () => {
    console.log('\n\n💾 Сохраняю статистику daemon...');
    statsManager.endSession();
    console.log('✅ Статистика сохранена.');
    process.exit(0);
});

process.on('SIGTERM', () => {
    console.log('\n\n💾 Завершение daemon, сохраняю статистику...');
    statsManager.endSession();
    process.exit(0);
});

startup();
