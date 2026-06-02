const express = require('express');
const path = require('path');
const os = require('os-utils');

// Логгер должен быть первым
const logger = require('../services/logger');

const temperatureReader = require('../core/temperature-linux');
const powerManager = require('../core/power-linux');
const batteryManager = require('../core/battery-linux');
const processManager = require('../core/processes-linux');
const autoControl = require('../core/auto-control-linux');
const statsManager = require('../services/stats');
const historyManager = require('../services/history');
const healthCheck = require('../services/health-check');
const logCleaner = require('../services/log-cleaner');

const apiRoutes = require('../api/routes');

const {
    PORT,
    AUTO_CONTROL_INTERVAL,
    STATS_SAVE_INTERVAL,
    HEALTH_CHECK_INTERVAL,
    LOG_CLEANUP_INTERVAL,
    TEMP_THRESHOLD
} = require('../config/constants');

const app = express();

// Health-check endpoint for monitoring
app.get('/healthz', (req, res) => {
  res.json({ ok: true, ts: Date.now() });
});

// Middleware
app.use(express.json());
app.use(express.static(path.join(__dirname, '..', '..', 'public')));

// API роуты
app.use('/api', apiRoutes);

// Получение нагрузки CPU
const getCpuLoad = () => {
    return new Promise((resolve) => {
        os.cpuUsage((v) => {
            resolve(v * 100);
        });
    });
};

// Автоматический контроль температуры
setInterval(async () => {
    try {
        const temp = await temperatureReader.getCpuTemperature();
        const load = await getCpuLoad();

        await autoControl.performAutoControl(temp, load);
    } catch (error) {
        console.error('❌ Ошибка автоконтроля:', error);
        logger.error('Ошибка автоконтроля: ' + error.message);
    }
}, AUTO_CONTROL_INTERVAL);

// Сохранение статистики каждые 30 секунд
setInterval(() => {
    statsManager.updateRuntime(30);
    statsManager.saveStats();
}, STATS_SAVE_INTERVAL);

// Проверка здоровья системы каждую минуту
setInterval(async () => {
    try {
        await healthCheck.performHealthCheck();
    } catch (error) {
        console.error('❌ Ошибка проверки здоровья:', error);
        logger.error('Ошибка проверки здоровья: ' + error.message);
    }
}, HEALTH_CHECK_INTERVAL);

// Очистка логов каждый час
setInterval(async () => {
    try {
        await logCleaner.performCleanup();
    } catch (error) {
        console.error('❌ Ошибка очистки логов:', error);
        logger.error('Ошибка очистки логов: ' + error.message);
    }
}, LOG_CLEANUP_INTERVAL);

// Запуск сервера
app.listen(PORT, async () => {
    console.log('\n════════════════════════════════════════════════');
    console.log('  🌡️ ТЕРМОРЕГУЛЯТОР CPU by @kasperenok (Linux)');
    console.log('════════════════════════════════════════════════\n');

    logger.info('Терморегулятор запущен на http://localhost:' + PORT);
    logger.info('Автоматический режим: ' + (autoControl.getAutoMode() ? 'ВКЛ' : 'ВЫКЛ'));
    logger.info('Интеллектуальный режим: ' + (autoControl.getIntelligentMode() ? 'ВКЛ' : 'ВЫКЛ'));

    // Проверяем реальное состояние турбо
    await powerManager.checkCurrentBoostState();
    console.log(`⚡ Турбо: ${powerManager.getTurboState() ? 'ВКЛ' : 'ВЫКЛ'}`);

    // Применяем текущее состояние при старте
    await powerManager.applyOnStartup();

    console.log(`\n⚠️  ВАЖНО: Для управления турбо/политиками могут нужны права sudo!`);
    console.log(`   Если команды не работают - запусти с sudo.\n`);

    // Статистика
    statsManager.printStats();

    // Проверка здоровья
    console.log('🔍 Проверка здоровья системы...');
    const health = await healthCheck.performHealthCheck();
    if (health.healthy) {
        console.log('✅ Все системы работают нормально\n');
    } else {
        console.log('⚠️ Обнаружены проблемы, но продолжаю работу\n');
    }

    // Очистка логов при старте если нужно
    const logsInfo = logCleaner.getLogsInfo();
    if (logsInfo.totalSize > 5 * 1024 * 1024) {
        console.log(`📦 Логи занимают ${(logsInfo.totalSize / 1024 / 1024).toFixed(2)} MB, запускаю очистку...`);
        await logCleaner.performCleanup();
    }

    // Сразу проверяем температуру
    try {
        const temp = await temperatureReader.getCpuTemperature();
        if (temp >= TEMP_THRESHOLD && powerManager.getTurboState()) {
            console.log(`🔥🔥🔥 ВНИМАНИЕ! Температура ${temp.toFixed(1)}°C при запуске! Отключаю турбо...`);
            await powerManager.setPowerMode(false);
        }
    } catch (e) {
        console.log('⚠️ Не удалось проверить температуру при старте');
    }

    // Сохранить статистику при выходе
    process.on('SIGINT', () => {
        console.log('\n\n💾 Сохраняю статистику...');
        statsManager.endSession();
        console.log('✅ Статистика сохранена. До встречи!');
        process.exit(0);
    });
});
