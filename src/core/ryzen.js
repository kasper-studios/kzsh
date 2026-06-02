const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');

class RyzenAdj {
    constructor() {
        this.enabled = false;
        this.ryzenAdjPath = null;
        this.stapmLimit = 15000; // 15W по умолчанию
        this.stapmLimitOff = 8000; // 8W для выключения буста
    }

    // Поиск RyzenAdj
    async findRyzenAdj() {
        return new Promise((resolve) => {
            // Проверяем возможные пути
            const possiblePaths = [
                path.join(__dirname, '..', '..', 'tools', 'RyzenAdj', 'ryzenadj.exe'),
                path.join(__dirname, '..', '..', 'RyzenAdj', 'ryzenadj.exe'),
                'C:\\Program Files\\RyzenAdj\\ryzenadj.exe',
                'C:\\Tools\\RyzenAdj\\ryzenadj.exe',
                path.join(process.env.APPDATA, 'RyzenAdj', 'ryzenadj.exe')
            ];

            for (const p of possiblePaths) {
                if (fs.existsSync(p)) {
                    this.ryzenAdjPath = p;
                    this.enabled = true;
                    console.log(`✅ RyzenAdj найден: ${p}`);
                    resolve(true);
                    return;
                }
            }

            // Проверяем PATH
            exec('where ryzenadj', (err) => {
                if (!err) {
                    this.ryzenAdjPath = 'ryzenadj';
                    this.enabled = true;
                    console.log('✅ RyzenAdj найден в PATH');
                    resolve(true);
                } else {
                    console.log('⚠️ RyzenAdj не найден. Скачай с https://github.com/FlyGoat/RyzenAdj/releases');
                    resolve(false);
                }
            });
        });
    }

    // Установка STAPM лимита (долгосрочный лимит мощности)
    setStapmLimit(limit) {
        return new Promise((resolve, reject) => {
            if (!this.enabled) {
                reject(new Error('RyzenAdj не найден'));
                return;
            }

            // Пробуем напрямую (если процесс уже от администратора)
            const cmd = `"${this.ryzenAdjPath}" --stapm-limit ${limit}`;
            console.log(`🔧 RyzenAdj: установка STAPM лимита ${limit}mW`);

            exec(cmd, { 
                encoding: 'utf8',
                windowsHide: true,
                shell: 'cmd.exe'
            }, (err, stdout, stderr) => {
                if (err) {
                    console.error(`❌ RyzenAdj ошибка: ${err.message}`);
                    if (stderr) console.error(`Stderr: ${stderr}`);
                    reject(err);
                } else {
                    if (stdout) console.log(stdout);
                    console.log(`✅ STAPM лимит установлен: ${limit}mW`);
                    this.stapmLimit = limit;
                    resolve(true);
                }
            });
        });
    }

    // Включение буста (высокий лимит)
    async enableBoost() {
        if (!this.enabled) return false;
        
        try {
            await this.setStapmLimit(this.stapmLimit);
            return true;
        } catch (e) {
            return false;
        }
    }

    // Выключение буста (низкий лимит)
    async disableBoost() {
        if (!this.enabled) return false;
        
        try {
            await this.setStapmLimit(this.stapmLimitOff);
            return true;
        } catch (e) {
            return false;
        }
    }

    // Проверка доступности
    isEnabled() {
        return this.enabled;
    }

    // Получить текущий лимит
    getStapmLimit() {
        return this.stapmLimit;
    }
}

module.exports = new RyzenAdj();
