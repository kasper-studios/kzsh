const express = require('express');
const path = require('path');
const os = require('os');
const fs = require('fs');

// Инициализация логгера (должен быть первым!)
const logger = require('./services/logger');

// Импорт модулей
const temperatureReader = require('./core/temperature');
const powerManager = require('./core/power');
const autoControl = require('./core/auto-control');
const statsManager = require('./services/stats');
const healthCheck = require('./services/health-check');
const logCleaner = require('./services/log-cleaner');
const apiRoutes = require('./api/routes');
const {
    PORT,
    AUTO_CONTROL_INTERVAL,
    STATS_SAVE_INTERVAL,
    HEALTH_CHECK_INTERVAL,
    LOG_CLEANUP_INTERVAL,
    TEMP_THRESHOLD
} = require('./config/constants');

const app = express();

// Middleware
app.use(express.json());
app.use(express.static(path.join(__dirname, '..', 'public')));

// API роуты
app.use('/api', apiRoutes);

// Получение нагрузки CPU для Linux
const getCpuLoad = () => {
    const avgLoad = os.loadavg()[0];
    const numCpus = os.cpus().length;
    const cpuUsage = (avgLoad / numCpus) * 100;
    return Promise.resolve(Math.min(cpuUsage, 100));
};

// Автоматический контроль температуры
setInterval(async () => {
    try {
        const temp = await temperatureReader.getCpuTemperature();
        const load = await getCpuLoad();

        await autoControl.performAutoControl(temp, load);
    } catch (error) {
        console.error('❌ Ошибка автоконтроля:', error);
    }
}, AUTO_CONTROL_INTERVAL);

// RyzenAdj отключен - не работает без доступа к драйверу ядра
// Управление бустом через powercfg + завершение процессов

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
    }
}, HEALTH_CHECK_INTERVAL);

// Очистка логов каждый час
setInterval(async () => {
    try {
        await logCleaner.performCleanup();
    } catch (error) {
        console.error('❌ Ошибка очистки логов:', error);
    }
}, LOG_CLEANUP_INTERVAL);

// Запуск сервера
app.listen(PORT, async () => {
    console.log('\n════════════════════════════════════════════════');
    console.log('  🌡️ ТЕРМОРЕГУЛЯТОР CPU by @kasperenok');
    console.log('════════════════════════════════════════════════\n');

    console.log(`🌡️  Терморегулятор запущен на http://localhost:${PORT}`);
    console.log(`⚙️  Автоматический режим: ${autoControl.getAutoMode() ? 'ВКЛ' : 'ВЫКЛ'}`);
    console.log(`🧠 Интеллектуальный режим: ${autoControl.getIntelligentMode() ? 'ВКЛ' : 'ВЫКЛ'}`);

    // Проверяем реальное состояние буста
    await powerManager.checkCurrentBoostState();
    console.log(`⚡ Турбобуст: ${powerManager.getTurboState() ? 'ВКЛ' : 'ВЫКЛ'}`);

    // Принудительно применяем текущее состояние буста чтобы записать настройку в схему питания
    await powerManager.applyOnStartup();

    console.log(`\n⚠️  ВАЖНО: Для управления турбобустом нужны права администратора!`);
    console.log(`   Если команды не работают - запусти от администратора.\n`);

    // Выводим статистику
    statsManager.printStats();

    // Проверяем здоровье системы при старте
    console.log('🔍 Проверка здоровья системы...');
    const health = await healthCheck.performHealthCheck();
    if (health.healthy) {
        console.log('✅ Все системы работают нормально\n');
    } else {
        console.log('⚠️ Обнаружены проблемы, но продолжаю работу\n');
    }

    // Проверяем логи при старте
    const logsInfo = logCleaner.getLogsInfo();
    if (logsInfo.totalSize > 5 * 1024 * 1024) { // Больше 5 MB
        console.log(`📦 Логи занимают ${(logsInfo.totalSize / 1024 / 1024).toFixed(2)} MB, запускаю очистку...`);
        await logCleaner.performCleanup();
    }

    // Сразу проверяем температуру
    const temp = await temperatureReader.getCpuTemperature();
    if (temp >= TEMP_THRESHOLD && powerManager.getTurboState()) {
        console.log(`🔥🔥🔥 ВНИМАНИЕ! Температура ${temp}°C при запуске! Отключаю буст...`);
        await powerManager.setPowerMode(false);
    }

    // Сохраняем статистику при выходе
    process.on('SIGINT', () => {
        console.log('\n\n💾 Сохраняю статистику...');
        statsManager.endSession();
        console.log('✅ Статистика сохранена. До встречи!');
        process.exit(0);
    });
});
