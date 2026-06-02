const { exec } = require('child_process');
const { BOOST_PROCESSES, PROCESS_CHECK_INTERVAL } = require('../config/constants');

class ProcessManager {
    constructor() {
        this.detectedProcesses = [];
        this.lastCheck = 0;
    }
    
    // Проверка запущенных процессов
    async checkBoostProcesses() {
        return new Promise((resolve) => {
            exec('tasklist /FO CSV /NH', (err, stdout) => {
                if (err || !stdout) {
                    console.log('⚠️ Ошибка получения списка процессов');
                    resolve([]);
                    return;
                }
                
                const running = [];
                const lowerOutput = stdout.toLowerCase();
                
                // Парсим CSV вывод - ищем процессы в кавычках
                for (const proc of BOOST_PROCESSES) {
                    const procName = proc.toLowerCase();
                    // Ищем процесс в формате "процесс.exe"
                    if (lowerOutput.includes(`"${procName}"`)) {
                        running.push(proc);
                    }
                }
                
                resolve(running);
            });
        });
    }
    
    // Обновление списка процессов (с учётом интервала)
    async updateProcesses() {
        const now = Date.now();
        if (now - this.lastCheck > PROCESS_CHECK_INTERVAL) {
            this.detectedProcesses = await this.checkBoostProcesses();
            this.lastCheck = now;
        }
        return this.detectedProcesses;
    }
    
    getDetectedProcesses() {
        return this.detectedProcesses;
    }

    hasBoostProcesses() {
        return this.detectedProcesses.length > 0;
    }

    // Завершение тяжёлых процессов (для аварийной ситуации)
    killHeavyProcesses() {
        console.log('⚰️  ЗАВЕРШАЮ ТЯЖЁЛЫЕ ПРОЦЕССЫ для охлаждения...');
        
        // Приоритетные для завершения (наиболее ресурсоёмкие)
        const priorityTargets = [
            'chrome.exe',
            'firefox.exe',
            'msedge.exe',
            'RobloxPlayerBeta.exe',
            'Unity.exe',
            'UnrealEditor.exe'
        ];

        for (const proc of priorityTargets) {
            try {
                exec(`taskkill /F /IM ${proc}`, (err) => {
                    if (!err) {
                        console.log(`  ✓ Завершён ${proc}`);
                    }
                });
            } catch (e) {
                // Игнорируем ошибки
            }
        }
    }

    // Принудительное завершение ВСЕХ процессов из списка
    killAllProcesses() {
        console.log('🆘 ЗАВЕРШАЮ ВСЕ ПРОЦЕССЫ из списка для спасения системы!');
        
        for (const proc of BOOST_PROCESSES) {
            try {
                exec(`taskkill /F /IM ${proc}`, (err) => {
                    if (!err) {
                        console.log(`  ✓ Завершён ${proc}`);
                    }
                });
            } catch (e) {
                // Игнорируем ошибки
            }
        }
    }
}

module.exports = new ProcessManager();
