const { exec } = require('child_process');
const { COOLDOWN } = require('../config/constants');

class PowerManager {
    constructor() {
        this.turboEnabled = true; // Считаем что буст включен по умолчанию
        this.lastBoostChange = Date.now();
        this.lastCheckedState = null;
        this.lastStateCheckTime = 0;
        this.stateCheckCacheMs = 3000; // Проверяем частоту раз в 3 секунды
        this.baseClockSpeed = 2400; // По умолчанию 2.4 ГГц
        this.hasCheckedBaseClock = false;
    }

    // Инициализация RyzenAdj (отключено)
    async initRyzenAdj() {
        // const ready = await ryzenAdj.findRyzenAdj();
        // return ready;
        return false; // Отключено
    }

    // Переключение на стандартную схему питания Windows (для управления бустом)
    async switchToStandardPowerScheme() {
        return new Promise((resolve) => {
            const standardScheme = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c';
            const cmd = `powercfg /setactive ${standardScheme}`;

            exec(cmd, { encoding: 'utf8' }, (err) => {
                // Даже если ошибка - помечаем как выполнено чтобы не повторять каждый цикл
                this.switchedToStandard = true;

                if (err) {
                    console.log('⚠️ Не удалось переключиться на стандартную схему питания');
                    resolve(false);
                    return;
                }

                console.log('✅ Переключено на стандартную схему питания Windows');

                const setMinCmd = `powercfg /setacvalueindex SCHEME_CURRENT ${this.PROCESSOR_SUB_GUID} ${this.PROCTHROTTLEMIN_GUID} 5 & powercfg /setdcvalueindex SCHEME_CURRENT ${this.PROCESSOR_SUB_GUID} ${this.PROCTHROTTLEMIN_GUID} 5`;
                exec(setMinCmd, { encoding: 'utf8' }, () => {
                    resolve(true);
                });
            });
        });
    }

    // Получение базовой и текущей частоты CPU
    async getCpuClockSpeeds() {
        return new Promise((resolve) => {
            const cmd = `powershell -Command "Get-CimInstance Win32_Processor | Measure-Object -Property CurrentClockSpeed -Average | Select-Object -ExpandProperty Average"`;

            exec(cmd, { encoding: 'utf8' }, (err, stdout) => {
                if (err || !stdout) {
                    resolve({ current: this.baseClockSpeed, max: this.baseClockSpeed * 1.7 });
                    return;
                }

                const currentClock = parseInt(stdout.trim());
                if (isNaN(currentClock)) {
                    resolve({ current: this.baseClockSpeed, max: this.baseClockSpeed * 1.7 });
                    return;
                }

                // Определяем базовую частоту (минимальное значение за несколько измерений)
                if (!this.hasCheckedBaseClock || currentClock < this.baseClockSpeed) {
                    this.baseClockSpeed = currentClock;
                    this.hasCheckedBaseClock = true;
                }

                // Максимальная частота с бустом (примерно базовая * 1.7 для AMD)
                const maxClock = this.baseClockSpeed * 1.7;

                resolve({ current: currentClock, max: maxClock, base: this.baseClockSpeed });
            });
        });
    }

    // Проверка текущего состояния через powercfg
    async checkCurrentBoostState() {
        return new Promise((resolve) => {
            const cmd = `chcp 65001 >nul 2>&1 & powercfg /query SCHEME_CURRENT ${this.PROCESSOR_SUB_GUID} ${this.PERFBOOSTMODE_GUID}`;

            exec(cmd, { encoding: 'utf8' }, (err, stdout) => {
                if (err || !stdout) {
                    console.log('⚠️ powercfg /query не ответил, доверяю внутреннему флагу');
                    resolve(this.turboEnabled);
                    return;
                }

                // Ищем последнее hex-значение после двоеточия в строке содержащей ' AC ' или 'сети'
                // EN: "Current AC Power Setting Index: 0x00000002"
                // RU: "Текущий индекс параметров электропитания от сети: 0x00000002"
                let matchedValue = null;
                const lines = stdout.split('\n');
                for (const line of lines) {
                    const lower = line.toLowerCase();
                    if (lower.includes(' ac ') || lower.includes('сети')) {
                        const m = line.match(/:\s*(0x[0-9a-fA-F]+)/);
                        if (m) {
                            matchedValue = parseInt(m[1], 16);
                            break;
                        }
                    }
                }

                // Fallback: берём последнее 0x... в выводе
                if (matchedValue === null) {
                    const allHex = [...stdout.matchAll(/0x([0-9a-fA-F]+)/g)];
                    if (allHex.length > 0) {
                        matchedValue = parseInt(allHex[allHex.length - 1][1], 16);
                        console.log(`⚠️ Использую fallback hex: 0x${matchedValue.toString(16)}`);
                    }
                }

                if (matchedValue === null) {
                    console.log('⚠️ Не удалось распарсить powercfg, доверяю внутреннему флагу');
                    resolve(this.turboEnabled);
                    return;
                }

                // 0 = Disabled, всё остальное (1=Enabled, 2=Aggressive, 4=Efficient) = включен
                const isEnabled = (matchedValue !== 0);
                console.log(`🔍 Буст: ${isEnabled ? 'ВКЛЮЧЕН' : 'ВЫКЛЮЧЕН'} (powercfg: 0x${matchedValue.toString(16)})`);

                this.turboEnabled = isEnabled;
                this.lastCheckedState = isEnabled;
                this.lastStateCheckTime = Date.now();
                resolve(isEnabled);
            });
        });
    }

    // Проверка буста по частоте CPU
    async checkBoostByClockSpeed() {
        const clocks = await this.getCpuClockSpeeds();

        // Фиксированный порог: без буста ~2401 МГц, с бустом 3000+ МГц
        // Порог 2600 МГц — надёжный детектор для данного железа
        const BOOST_CLOCK_THRESHOLD = 2600;
        const isEnabled = clocks.current > BOOST_CLOCK_THRESHOLD;

        console.log(`🔍 Буст: ${isEnabled ? 'ВКЛЮЧЕН' : 'ВЫКЛЮЧЕН'} (частота: ${clocks.current} МГц)`);

        this.turboEnabled = isEnabled;
        this.lastCheckedState = isEnabled;
        this.lastStateCheckTime = Date.now();

        return isEnabled;
    }

    // Получение состояния буста с проверкой по частоте (кэш 3 секунды)
    async getRealTurboState() {
        const now = Date.now();
        if (this.lastStateCheckTime && (now - this.lastStateCheckTime) < this.stateCheckCacheMs) {
            return this.lastCheckedState !== null ? this.lastCheckedState : this.turboEnabled;
        }
        return await this.checkBoostByClockSpeed();
    }

    // Быстрый доступ к последнему известному состоянию
    getTurboState() {
        return this.turboEnabled;
    }

    // Синхронизация состояния после setPowerMode
    async setPowerMode(isMax) {
        // Используем powercfg (RyzenAdj отключен)
        return this._setPowerModePowerCfg(isMax);
    }

    // Управление через powercfg
    async _setPowerModePowerCfg(isMax) {
        return new Promise((resolve, reject) => {
            // Сначала переключаемся на стандартную схему если нужно
            if (!this.switchedToStandard) {
                this.switchToStandardPowerScheme().then(() => {
                    this._applyPowerMode(isMax, resolve, reject);
                });
            } else {
                this._applyPowerMode(isMax, resolve, reject);
            }
        });
    }

    // Применение настройки при старте (без сброса кулдауна)
    async applyOnStartup() {
        return new Promise((resolve) => {
            if (!this.switchedToStandard) {
                this.switchToStandardPowerScheme().then(() => {
                    this._applyStartupMode(resolve);
                });
            } else {
                this._applyStartupMode(resolve);
            }
        });
    }

    _applyStartupMode(resolve) {
        const val = this.turboEnabled ? 2 : 0;
        const cmd = `chcp 65001 >nul 2>&1 & powercfg /setacvalueindex SCHEME_CURRENT ${this.PROCESSOR_SUB_GUID} ${this.PERFBOOSTMODE_GUID} ${val} & powercfg /setdcvalueindex SCHEME_CURRENT ${this.PROCESSOR_SUB_GUID} ${this.PERFBOOSTMODE_GUID} ${val} & powercfg /setactive SCHEME_CURRENT`;
        exec(cmd, { encoding: 'utf8' }, (err, stdout, stderr) => {
            if (err) {
                console.log(`⚠️ Не удалось применить настройку буста при старте: ${err.message}`);
            } else {
                console.log(`✅ Буст применён при старте (индекс: ${val})`);
            }
            resolve(!err);
        });
    }

    // Применение режима питания (после переключения схемы)
    _applyPowerMode(isMax, resolve, reject) {
        // Устанавливаем режим буста (Performance Boost Mode): 2 = Aggressive, 0 = Disabled
        const val = isMax ? 2 : 0;
        const cmd = `chcp 65001 >nul 2>&1 & powercfg /setacvalueindex SCHEME_CURRENT ${this.PROCESSOR_SUB_GUID} ${this.PERFBOOSTMODE_GUID} ${val} & powercfg /setdcvalueindex SCHEME_CURRENT ${this.PROCESSOR_SUB_GUID} ${this.PERFBOOSTMODE_GUID} ${val} & powercfg /setactive SCHEME_CURRENT`;

        console.log(`🔧 Выполняю команду: ${isMax ? 'ВКЛЮЧИТЬ' : 'ВЫКЛЮЧИТЬ'} турбобуст (индекс: ${val})`);

        exec(cmd, { encoding: 'utf8' }, (err, stdout, stderr) => {
            if (err) {
                console.error("❌ Ошибка выполнения powercfg:", err.message);
                console.error("Stderr:", stderr);
                console.error("⚠️ ВОЗМОЖНО НУЖНЫ ПРАВА АДМИНИСТРАТОРА!");
                reject(err);
            } else {
                this.turboEnabled = isMax;
                this.lastBoostChange = Date.now();
                // Сбрасываем кэш чтобы следующая проверка была актуальной
                this.lastStateCheckTime = 0;
                console.log(isMax ? "✅ ВРУБИЛ ПОЛНУЮ!" : "✅ ОТДЫХАЕМ...");
                if (stdout) console.log("Stdout:", stdout);
                resolve();
            }
        });
    }

    // Проверка cooldown
    canChange() {
        const timeSinceLastChange = Date.now() - this.lastBoostChange;
        return timeSinceLastChange > COOLDOWN;
    }

    // Получение времени до следующего возможного переключения
    getTimeUntilNextChange() {
        const timeSinceLastChange = Date.now() - this.lastBoostChange;
        const remaining = COOLDOWN - timeSinceLastChange;
        return remaining > 0 ? Math.ceil(remaining / 1000) : 0;
    }

    getTurboState() {
        return this.turboEnabled;
    }
}

module.exports = new PowerManager();
