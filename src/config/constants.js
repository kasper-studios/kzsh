// Константы и настройки приложения

module.exports = {
    // Сервер
    PORT: 9110,
    
    // Пороги температуры
    TEMP_THRESHOLD: 90,      // Критический перегрев
    TEMP_HIGH: 87,           // Высокая температура - выключаем буст
    TEMP_SAFE: 70,           // Безопасная температура - можно включать буст
    TEMP_MEDIUM: 75,         // Средняя температура
    IDLE_TEMP_THRESHOLD: 82, // Порог для простоя
    
    // Нагрузка CPU
    IDLE_LOAD_THRESHOLD: 10, // Считаем простоем если нагрузка < 10%
    HIGH_LOAD_THRESHOLD: 50, // Высокая нагрузка
    
    // Гистерезис
    COOLDOWN: 30000,         // 30 секунд между повышением профиля (boost up)
    COOLDOWN_DOWN: 5000,     // 5 секунд между понижением профиля (экстренное охлаждение)
    
    // История и тренд температуры
    TEMP_HISTORY_SIZE: 5,          // Храним последние 5 значений для анализа тренда
    TEMP_TREND_WINDOW: 5,          // Окно скользящего среднего для тренда (точек)
    TEMP_TREND_RISE_THRESHOLD: 1.5, // Скорость роста °C/тик при которой снижаем порог
    TEMP_TREND_SAFE_OFFSET: 5,     // На сколько °C снизить TEMP_HIGH при быстром росте
    
    // Батарея
    BATTERY_CHECK_INTERVAL: 10000, // Проверяем батарею раз в 10 секунд
    MIN_BATTERY_LEVEL: 50,         // Минимальный уровень заряда для буста
    
    // Процессы
    PROCESS_CHECK_INTERVAL: 5000,  // Проверяем процессы раз в 5 секунд
    BOOST_PROCESSES: [
        'RobloxPlayerBeta.exe',
        'RobloxStudioBeta.exe',
        'javaw.exe',           // Minecraft
        'chrome.exe',
        'firefox.exe',
        'msedge.exe',
        'Code.exe',            // VS Code
        'devenv.exe',          // Visual Studio
        'Unity.exe',
        'UnrealEditor.exe'
    ],
    
    // Периоды истории для графиков
    HISTORY_PERIODS: {
        '2min': { maxPoints: 60, interval: 2000 },   // 60 точек * 2 сек = 2 минуты
        '5min': { maxPoints: 150, interval: 2000 },  // 150 точек * 2 сек = 5 минут
        '10min': { maxPoints: 300, interval: 2000 }, // 300 точек * 2 сек = 10 минут
        '1hour': { maxPoints: 360, interval: 10000 } // 360 точек * 10 сек = 1 час
    },
    
    // Интервалы
    AUTO_CONTROL_INTERVAL: 2000,   // Проверка температуры каждые 2 секунды
    STATS_SAVE_INTERVAL: 30000,    // Сохранение статистики каждые 30 секунд
    HEALTH_CHECK_INTERVAL: 60000,  // Проверка здоровья системы каждую минуту
    LOG_CLEANUP_INTERVAL: 3600000, // Проверка логов каждый час
    
    // Пути
    LOG_DIR: '.logs',
    STATS_FILE: '.logs/stats.json',
    LOG_FILE: '.logs/termoregulator.log'
};
