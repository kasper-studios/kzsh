// Константы и настройки приложения

module.exports = {
    PORT: 9110,
    
    TEMP_THRESHOLD: 90,
    TEMP_HIGH: 87,
    TEMP_SAFE: 60,
    TEMP_MEDIUM: 70,
    IDLE_TEMP_THRESHOLD: 65,
    
    IDLE_LOAD_THRESHOLD: 10,
    HIGH_LOAD_THRESHOLD: 50,
    
    COOLDOWN: 30000,
    TEMP_HISTORY_SIZE: 5,
    
    AUTO_CONTROL_INTERVAL: 2000,
    STATS_SAVE_INTERVAL: 30000,
    HEALTH_CHECK_INTERVAL: 60000,
    LOG_CLEANUP_INTERVAL: 3600000,
    
    LOG_DIR: '.logs',
    STATS_FILE: '.logs/stats.json',
    LOG_FILE: '.logs/termoregulator.log'
};