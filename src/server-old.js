const express = require('express');
const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');
const { getCpuTemperature } = require('./temp-reader');
const os = require('os-utils');

const app = express();
const PORT = 9110;

// Логирование в файл
const LOG_FILE = path.join(__dirname, 'termoregulator.log');
const originalLog = console.log;
const originalError = console.error;

// Функция для записи в лог
const writeLog = (message, isError = false) => {
    const timestamp = new Date().toLocaleString('ru-RU');
    const logMessage = `[${timestamp}] ${message}\n`;
    
    // Пишем в файл
    fs.appendFileSync(LOG_FILE, logMessage, 'utf8');
    
    // Выводим в консоль (если она видна)
    if (isError) {
        originalError(message);
    } else {
        originalLog(message);
    }
};

// Переопределяем console.log и console.error
console.log = (...args) => writeLog(args.join(' '));
console.error = (...args) => writeLog(args.join(' '), true);

// Файл статистики
const STATS_FILE = path.join(__dirname, 'stats.json');
console.log('\n════════════════════════════════════════════════');
console.log('  🌡️ ТЕРМОРЕГУЛЯТОР CPU by @kasperenok');
console.log('════════════════════════════════════════════════\n');

// Загрузка статистики
let stats = {
    owner: '@kasperenok',
    totalSessions: 0,
    overheatingPrevented: 0,
    totalRuntime: 0, // в секундах
    longestSession: 0, // в секундах
    maxTemperature: 0,
    avgTemperature: 0,
    tempSum: 0,
    tempCount: 0,
    firstStart: null,
    lastStart: null
};

// Загружаем статистику из файла
if (fs.existsSync(STATS_FILE)) {
    try {
        const data = fs.readFileSync(STATS_FILE, 'utf8');
        stats = { ...stats, ...JSON.parse(data) };
        console.log('📊 Статистика загружена');
    } catch (e) {
        console.log('⚠️ Ошибка загрузки статистики, создаю новую');
    }
}

// Текущая сессия
const sessionStart = Date.now();
stats.totalSessions++;
stats.lastStart = new Date().toISOString();
if (!stats.firstStart) {
    stats.firstStart = stats.lastStart;
}

// Сохранение статистики
const saveStats = () => {
    try {
        fs.writeFileSync(STATS_FILE, JSON.stringify(stats, null, 2));
    } catch (e) {
        console.error('❌ Ошибка сохранения статистики:', e.message);
    }
};

// Обновление статистики температуры
const updateTempStats = (temp) => {
    stats.tempSum += temp;
    stats.tempCount++;
    stats.avgTemperature = stats.tempSum / stats.tempCount;
    
    if (temp > stats.maxTemperature) {
        stats.maxTemperature = temp;
    }
};

// Сохраняем статистику каждые 30 секунд
setInterval(() => {
    const currentSessionTime = Math.floor((Date.now() - sessionStart) / 1000);
    stats.totalRuntime += 30; // Добавляем 30 секунд
    
    if (currentSessionTime > stats.longestSession) {
        stats.longestSession = currentSessionTime;
    }
    
    saveStats();
}, 30000);

let autoMode = true; // Автоматический режим включен по умолчанию
let intelligentMode = true; // Умный режим включен по умолчанию
let turboEnabled = true; // Считаем что буст включен по умолчанию (безопаснее)

// Пороги температуры
const TEMP_THRESHOLD = 90; // Критический перегрев
const TEMP_HIGH = 87; // Высокая температура - выключаем буст
const TEMP_SAFE = 70; // Безопасная температура - можно включать буст
const TEMP_MEDIUM = 75; // Средняя температура
const IDLE_TEMP_THRESHOLD = 82; // Порог для простоя
const IDLE_LOAD_THRESHOLD = 10; // Считаем простоем если нагрузка < 10%

// Гистерезис - задержка между переключениями
let lastBoostChange = Date.now();
const COOLDOWN = 30000; // 30 секунд между переключениями

// Детект тренда температуры
let tempHistory = [];
const TEMP_HISTORY_SIZE = 5; // Храним последние 5 значений

// Счётчик спасений от перегрева (используем из stats)
let overheatingPreventionCount = stats.overheatingPrevented;

// Состояние батареи
let batteryStatus = {
    isCharging: true,
    level: 100,
    lastCheck: 0
};

const BATTERY_CHECK_INTERVAL = 10000; // Проверяем батарею раз в 10 секунд
const MIN_BATTERY_LEVEL = 50; // Минимальный уровень заряда для буста

// История для графика
const history = {
    temps: [],
    loads: [],
    timestamps: [],
    turboStates: []
};

// Разные периоды истории
const historyPeriods = {
    '2min': { maxPoints: 60, interval: 2000 },   // 60 точек * 2 сек = 2 минуты
    '5min': { maxPoints: 150, interval: 2000 },  // 150 точек * 2 сек = 5 минут
    '10min': { maxPoints: 300, interval: 2000 }, // 300 точек * 2 сек = 10 минут
    '1hour': { maxPoints: 360, interval: 10000 } // 360 точек * 10 сек = 1 час
};

let currentPeriod = '2min';

// Список процессов которые требуют буста
const BOOST_PROCESSES = [
    'RobloxPlayerBeta.exe',
    'RobloxStudioBeta.exe',
    'javaw.exe', // Minecraft
    'chrome.exe',
    'firefox.exe',
    'msedge.exe',
    'Code.exe', // VS Code
    'devenv.exe', // Visual Studio
    'Unity.exe',
    'UnrealEditor.exe'
];

let detectedProcesses = [];

app.use(express.json());
app.use(express.static('public'));

// Проверка состояния батареи
const checkBatteryStatus = () => {
    return new Promise((resolve) => {
        exec('powershell -Command "Get-WmiObject Win32_Battery | Select-Object BatteryStatus, EstimatedChargeRemaining | ConvertTo-Json"', (err, stdout) => {
            if (err) {
                // Если не удалось проверить - считаем что на зарядке
                resolve({ isCharging: true, level: 100 });
                return;
            }
            
            try {
                const data = JSON.parse(stdout.trim());
                const isCharging = data.BatteryStatus === 2; // 2 = charging, 1 = discharging
                const level = data.EstimatedChargeRemaining || 100;
                
                resolve({ isCharging, level });
            } catch (e) {
                // Если парсинг не удался - считаем что на зарядке
                resolve({ isCharging: true, level: 100 });
            }
        });
    });
};

// Проверка текущего состояния турбобуста
const checkCurrentBoostState = () => {
    return new Promise(async (resolve) => {
        // Сначала пробуем через powercfg
        exec('powercfg /query SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 be337238-0d82-4146-a960-4f3749d470c7', (err, stdout) => {
            if (err) {
                console.log('⚠️ Не удалось проверить состояние буста через powercfg');
                // Пробуем угадать по температуре
                guessBoostStateByTemp().then(resolve);
                return;
            }
            
            // Ищем строку с Current AC Power Setting Index
            const match = stdout.match(/Current AC Power Setting Index: (0x[0-9a-f]+)/i);
            if (match) {
                const value = parseInt(match[1], 16);
                const isEnabled = value === 2;
                console.log(`🔍 Текущее состояние буста: ${isEnabled ? 'ВКЛЮЧЕН' : 'ВЫКЛЮЧЕН'} (значение: ${value})`);
                resolve(isEnabled);
            } else {
                console.log('⚠️ Не удалось распарсить состояние буста');
                // Пробуем угадать по температуре
                guessBoostStateByTemp().then(resolve);
            }
        });
    });
};

// Угадываем состояние буста по температуре
const guessBoostStateByTemp = async () => {
    const temp = await getCpuTemperature();
    
    // Если температура низкая (< 65°C) - скорее всего буст выключен
    if (temp < 65) {
        console.log(`🔍 Температура ${temp}°C низкая - скорее всего буст ВЫКЛЮЧЕН`);
        return false;
    }
    // Если температура высокая (> 75°C) - скорее всего буст включен
    else if (temp > 75) {
        console.log(`🔍 Температура ${temp}°C высокая - скорее всего буст ВКЛЮЧЕН`);
        return true;
    }
    // Средняя температура - считаем что включен (безопаснее)
    else {
        console.log(`🔍 Температура ${temp}°C средняя - считаем что буст ВКЛЮЧЕН (безопаснее)`);
        return true;
    }
};
const setPowerMode = (isMax) => {
    return new Promise((resolve, reject) => {
        const val = isMax ? 2 : 0;
        const cmd = `powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 be337238-0d82-4146-a960-4f3749d470c7 ${val} & powercfg /setactive SCHEME_CURRENT`;
        
        console.log(`🔧 Выполняю команду: ${isMax ? 'ВКЛЮЧИТЬ' : 'ВЫКЛЮЧИТЬ'} турбобуст`);
        
        exec(cmd, (err, stdout, stderr) => {
            if (err) {
                console.error("❌ Ошибка выполнения powercfg:", err.message);
                console.error("Stderr:", stderr);
                console.error("⚠️ ВОЗМОЖНО НУЖНЫ ПРАВА АДМИНИСТРАТОРА!");
                reject(err);
            } else {
                turboEnabled = isMax;
                lastBoostChange = Date.now(); // Запоминаем время последнего переключения
                console.log(isMax ? "✅ ВРУБИЛ ПОЛНУЮ!" : "✅ ОТДЫХАЕМ...");
                if (stdout) console.log("Stdout:", stdout);
                resolve();
            }
        });
    });
};

// Получение нагрузки CPU
const getCpuLoad = () => {
    return new Promise((resolve) => {
        os.cpuUsage((v) => {
            resolve(v * 100);
        });
    });
};

// Проверка запущенных процессов
const checkBoostProcesses = () => {
    return new Promise((resolve) => {
        exec('tasklist /FO CSV /NH', (err, stdout) => {
            if (err) {
                resolve([]);
                return;
            }
            
            const running = [];
            
            // Парсим CSV вывод (формат: "имя.exe","PID","Session","Session#","Mem Usage")
            for (const proc of BOOST_PROCESSES) {
                const procName = proc.toLowerCase();
                // Ищем процесс в кавычках в начале строки
                const regex = new RegExp(`"${procName}"`, 'i');
                if (regex.test(stdout)) {
                    running.push(proc);
                }
            }
            
            resolve(running);
        });
    });
};

// Добавление в историю
const addToHistory = (temp, load, turbo) => {
    const now = new Date().toLocaleTimeString('ru-RU');
    
    history.temps.push(temp);
    history.loads.push(load);
    history.timestamps.push(now);
    history.turboStates.push(turbo);
    
    // Храним только нужное количество точек для текущего периода
    const maxPoints = historyPeriods[currentPeriod].maxPoints;
    if (history.temps.length > maxPoints) {
        history.temps.shift();
        history.loads.shift();
        history.timestamps.shift();
        history.turboStates.shift();
    }
};

// Получение истории для графика
app.get('/api/history', (req, res) => {
    const period = req.query.period || currentPeriod;
    res.json({
        ...history,
        currentPeriod: period
    });
});

// Изменение периода истории
app.post('/api/history/period', (req, res) => {
    const newPeriod = req.body.period;
    if (historyPeriods[newPeriod]) {
        currentPeriod = newPeriod;
        // Очищаем историю при смене периода
        history.temps = [];
        history.loads = [];
        history.timestamps = [];
        history.turboStates = [];
        res.json({ success: true, period: currentPeriod });
    } else {
        res.status(400).json({ error: 'Invalid period' });
    }
});

// Получение статуса
app.get('/api/status', async (req, res) => {
    try {
        const temperature = await getCpuTemperature();
        const load = await getCpuLoad();
        
        // Обновляем статистику температуры
        updateTempStats(temperature);
        
        // Обновляем историю
        addToHistory(temperature, load, turboEnabled);
        
        res.json({
            temperature: temperature,
            load: load.toFixed(1),
            turboEnabled,
            autoMode,
            intelligentMode,
            detectedProcesses,
            saveCount: overheatingPreventionCount,
            battery: batteryStatus,
            stats: {
                ...stats,
                currentSessionTime: Math.floor((Date.now() - sessionStart) / 1000)
            }
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Получение истории для графика
app.get('/api/history', (req, res) => {
    res.json(history);
});

// Ручное управление турбо
app.post('/api/turbo', async (req, res) => {
    try {
        const { enabled } = req.body;
        await setPowerMode(enabled);
        res.json({ success: true, turboEnabled });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Переключение автоматического режима
app.post('/api/auto', (req, res) => {
    autoMode = req.body.enabled;
    res.json({ success: true, autoMode });
});

// Переключение интеллектуального режима
app.post('/api/intelligent', (req, res) => {
    intelligentMode = req.body.enabled;
    res.json({ success: true, intelligentMode });
});

// Анализ тренда температуры
const analyzeTempTrend = (currentTemp) => {
    tempHistory.push(currentTemp);
    if (tempHistory.length > TEMP_HISTORY_SIZE) {
        tempHistory.shift();
    }
    
    if (tempHistory.length < 3) return { trend: 'unknown', rate: 0 };
    
    // Вычисляем скорость роста температуры
    const oldTemp = tempHistory[0];
    const rate = (currentTemp - oldTemp) / tempHistory.length;
    
    let trend = 'stable';
    if (rate > 1) trend = 'rising-fast'; // Растёт быстро (>1°C за цикл)
    else if (rate > 0.5) trend = 'rising'; // Растёт умеренно
    else if (rate < -1) trend = 'falling-fast'; // Падает быстро
    else if (rate < -0.5) trend = 'falling'; // Падает умеренно
    
    return { trend, rate: rate.toFixed(2) };
};

// Автоматический контроль температуры
let lastProcessCheck = 0;
const PROCESS_CHECK_INTERVAL = 5000; // Проверяем процессы раз в 5 секунд

setInterval(async () => {
    if (!autoMode) return;
    
    try {
        const temp = await getCpuTemperature();
        const load = await getCpuLoad();
        
        // Проверяем батарею раз в 10 секунд
        const now = Date.now();
        if (now - batteryStatus.lastCheck > BATTERY_CHECK_INTERVAL) {
            batteryStatus = await checkBatteryStatus();
            batteryStatus.lastCheck = now;
        }
        
        // ПРОВЕРКА БАТАРЕИ - отключаем буст если не на зарядке или заряд < 50%
        if (!batteryStatus.isCharging || batteryStatus.level < MIN_BATTERY_LEVEL) {
            if (turboEnabled) {
                console.log(`🔋 Батарея: ${batteryStatus.isCharging ? 'зарядка' : 'отключена'}, ${batteryStatus.level}% - отключаю буст`);
                await setPowerMode(false);
            }
            return; // Не продолжаем проверки, пока не на зарядке
        }
        
        // Анализируем тренд температуры
        const { trend, rate } = analyzeTempTrend(temp);
        
        // Проверяем процессы не каждый раз, а раз в 5 секунд
        if (now - lastProcessCheck > PROCESS_CHECK_INTERVAL) {
            detectedProcesses = await checkBoostProcesses();
            lastProcessCheck = now;
        }
        
        // Проверяем cooldown
        const timeSinceLastChange = now - lastBoostChange;
        const canChange = timeSinceLastChange > COOLDOWN;
        
        console.log(`📊 ${temp.toFixed(1)}°C (${trend} ${rate}°C/цикл), ${load.toFixed(1)}%, Буст: ${turboEnabled ? 'ВКЛ' : 'ВЫКЛ'}, Cooldown: ${canChange ? 'OK' : Math.ceil((COOLDOWN - timeSinceLastChange) / 1000) + 's'}`);
        
        // КРИТИЧЕСКАЯ ЗАЩИТА (игнорирует cooldown)
        if (temp >= TEMP_THRESHOLD && turboEnabled) {
            console.log(`🔥🔥🔥 ПЕРЕГРЕВ ${temp}°C! АВАРИЙНОЕ ОТКЛЮЧЕНИЕ БУСТА!`);
            overheatingPreventionCount++;
            stats.overheatingPrevented = overheatingPreventionCount;
            saveStats();
            await setPowerMode(false);
            return;
        } else if (temp >= TEMP_THRESHOLD && !turboEnabled) {
            console.log(`🔥 КРИТИЧЕСКАЯ ТЕМПЕРАТУРА ${temp}°C! Буст уже выключен.`);
            return;
        }
        
        // ПРЕДИКТИВНОЕ ВЫКЛЮЧЕНИЕ - если температура растёт слишком быстро
        if (trend === 'rising-fast' && temp > TEMP_MEDIUM && turboEnabled) {
            console.log(`⚠️ Температура растёт быстро (${rate}°C/цикл) при ${temp}°C - превентивно отключаю буст`);
            overheatingPreventionCount++;
            stats.overheatingPrevented = overheatingPreventionCount;
            saveStats();
            await setPowerMode(false);
            return;
        }
        
        // Интеллектуальный режим (с учетом cooldown)
        if (intelligentMode && canChange) {
            // Если есть важные процессы - разрешаем буст (но не при высокой температуре)
            if (detectedProcesses.length > 0) {
                if (!turboEnabled && temp < TEMP_HIGH) {
                    console.log(`🎮 Обнаружены процессы: ${detectedProcesses.join(', ')} - включаю буст (${temp}°C)`);
                    await setPowerMode(true);
                }
            }
            // Если простой и жарко - вырубаем буст
            else if (load < IDLE_LOAD_THRESHOLD && temp > IDLE_TEMP_THRESHOLD && turboEnabled) {
                console.log(`💤 Простой (${load.toFixed(1)}%) + жарко (${temp}°C) - отключаю буст`);
                await setPowerMode(false);
            }
            // Если нагрузка есть и температура БЕЗОПАСНАЯ - включаем буст
            else if (load >= IDLE_LOAD_THRESHOLD && temp < TEMP_SAFE && !turboEnabled) {
                console.log(`⚡ Нагрузка ${load.toFixed(1)}% + температура ${temp}°C (безопасно) - включаю буст`);
                await setPowerMode(true);
            }
            // Если высокая нагрузка и температура ВЫСОКАЯ - вырубаем буст
            else if (load > 50 && temp > TEMP_HIGH && turboEnabled) {
                console.log(`🔥 Высокая нагрузка ${load.toFixed(1)}% + жарко ${temp}°C - отключаю буст`);
                await setPowerMode(false);
            }
        }
        
        // Базовый режим (без интеллекта, но с cooldown)
        if (!intelligentMode && canChange) {
            if (temp < TEMP_SAFE && !turboEnabled) {
                console.log(`❄️ Температура ${temp}°C (безопасно) - включаю буст`);
                await setPowerMode(true);
            } else if (temp > TEMP_HIGH && turboEnabled) {
                console.log(`🔥 Температура ${temp}°C (высокая) - отключаю буст`);
                await setPowerMode(false);
            }
        }
    } catch (error) {
        console.error('❌ Ошибка автоконтроля:', error);
    }
}, 2000);

app.listen(PORT, async () => {
    console.log(`🌡️  Терморегулятор запущен на http://localhost:${PORT}`);
    console.log(`⚙️  Автоматический режим: ${autoMode ? 'ВКЛ' : 'ВЫКЛ'}`);
    console.log(`🧠 Интеллектуальный режим: ${intelligentMode ? 'ВКЛ' : 'ВЫКЛ'}`);
    
    // Проверяем реальное состояние буста
    turboEnabled = await checkCurrentBoostState();
    console.log(`⚡ Турбобуст: ${turboEnabled ? 'ВКЛ' : 'ВЫКЛ'}`);
    
    console.log(`\n⚠️  ВАЖНО: Для управления турбобустом нужны права администратора!`);
    console.log(`   Если команды не работают - запусти от администратора.\n`);
    
    // Выводим статистику
    const formatTime = (seconds) => {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        if (hours > 0) return `${hours}ч ${minutes}м`;
        return `${minutes}м`;
    };
    
    console.log(`\n📊 СТАТИСТИКА ЗА ВРЕМЯ ВЛАДЕНИЯ ${stats.owner}:`);
    console.log(`   • Всего сессий: ${stats.totalSessions}`);
    console.log(`   • Спасено от перегрева: ${stats.overheatingPrevented} раз`);
    console.log(`   • Средняя температура: ${stats.avgTemperature.toFixed(1)}°C`);
    console.log(`   • Самая высокая температура: ${stats.maxTemperature.toFixed(1)}°C`);
    console.log(`   • Общее время работы: ${formatTime(stats.totalRuntime)}`);
    console.log(`   • Самая длинная сессия: ${formatTime(stats.longestSession)}`);
    console.log(`   • Первый запуск: ${stats.firstStart ? new Date(stats.firstStart).toLocaleString('ru-RU') : 'сейчас'}\n`);
    
    // Сразу проверяем температуру
    const temp = await getCpuTemperature();
    if (temp >= TEMP_THRESHOLD && turboEnabled) {
        console.log(`🔥🔥🔥 ВНИМАНИЕ! Температура ${temp}°C при запуске! Отключаю буст...`);
        await setPowerMode(false);
    }
    
    // Сохраняем статистику при выходе
    process.on('SIGINT', () => {
        console.log('\n\n💾 Сохраняю статистику...');
        const currentSessionTime = Math.floor((Date.now() - sessionStart) / 1000);
        stats.totalRuntime += currentSessionTime;
        if (currentSessionTime > stats.longestSession) {
            stats.longestSession = currentSessionTime;
        }
        saveStats();
        console.log('✅ Статистика сохранена. До встречи!');
        process.exit(0);
    });
});
