// Constants and application settings

const path = require('path');

const PROJECT_ROOT = path.resolve(__dirname, '..', '..');
const LOG_DIR = path.join(PROJECT_ROOT, '.logs');

const HISTORY_PERIODS = Object.freeze({
    '2min': { maxPoints: 60, interval: 2000 },
    '5min': { maxPoints: 150, interval: 2000 },
    '10min': { maxPoints: 300, interval: 2000 },
    '1hour': { maxPoints: 360, interval: 10000 }
});

const BOOST_PROCESSES = Object.freeze([
    { name: 'Minecraft / Java', patterns: ['java', 'javaw', 'minecraft', 'minecraft-launcher'] },
    { name: 'VS Code', patterns: ['code', 'code-insiders', 'codium'] },
    { name: 'Google Chrome', patterns: ['chrome', 'google-chrome'] },
    { name: 'Chromium', patterns: ['chromium', 'chromium-browser'] },
    { name: 'Firefox', patterns: ['firefox', 'firefox-bin'] },
    { name: 'Steam', patterns: ['steam', 'steamwebhelper'] },
    { name: 'Lutris', patterns: ['lutris'] },
    { name: 'Heroic Games Launcher', patterns: ['heroic', 'heroic-games-launcher'] },
    { name: 'OBS Studio', patterns: ['obs', 'obs-studio'] },
    { name: 'Unity Editor', patterns: ['unity', 'unityhub'] },
    { name: 'Unreal Engine', patterns: ['unreal', 'ue4editor', 'unrealeditor'] },
    { name: 'Roblox / Wine', patterns: ['roblox', 'robloxplayerbeta.exe', 'wine64', 'wine-preloader'] },
    { name: 'Blender', patterns: ['blender'] },
    { name: 'JetBrains IDE', patterns: ['idea', 'pycharm', 'webstorm', 'clion', 'phpstorm', 'goland', 'rider'] }
]);

module.exports = Object.freeze({
    // Server
    PORT: 9110,

    // Temperature thresholds
    TEMP_THRESHOLD: 90,
    TEMP_HIGH: 87,
    TEMP_SAFE: 70,
    TEMP_MEDIUM: 75,
    IDLE_TEMP_THRESHOLD: 82,

    // CPU load thresholds
    IDLE_LOAD_THRESHOLD: 10,
    HIGH_LOAD_THRESHOLD: 50,

    // Switching hysteresis
    COOLDOWN: 30000,

    // Temperature trend history
    TEMP_HISTORY_SIZE: 5,

    // Battery protection
    BATTERY_CHECK_INTERVAL: 10000,
    MIN_BATTERY_LEVEL: 50,

    // Process detection
    PROCESS_CHECK_INTERVAL: 5000,
    BOOST_PROCESSES,

    // Chart history periods
    HISTORY_PERIODS,

    // Background intervals
    AUTO_CONTROL_INTERVAL: 2000,
    STATS_SAVE_INTERVAL: 30000,
    HEALTH_CHECK_INTERVAL: 60000,
    LOG_CLEANUP_INTERVAL: 3600000,

    // Paths
    PROJECT_ROOT,
    LOG_DIR,
    STATS_FILE: path.join(LOG_DIR, 'stats.json'),
    LOG_FILE: path.join(LOG_DIR, 'termoregulator.log'),

    // Logs
    MAX_LOG_AGE: 7 * 24 * 60 * 60 * 1000,
    MAX_LOG_SIZE: 10 * 1024 * 1024
});
