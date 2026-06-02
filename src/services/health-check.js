const { exec } = require('child_process');
const path = require('path');

class HealthCheck {
    constructor() {
        this.lastCheck = 0;
        this.checkInterval = 30000; // Проверка каждые 30 секунд
        this.libreHWPath = path.join(__dirname, '..', '..', 'LibreHardwareMonitor', 'LibreHardwareMonitor.exe');
        this.libreHWRestartAttempts = 0;
        this.maxRestartAttempts = 3;
    }
    
    // Проверка запущен ли LibreHardwareMonitor
    async checkLibreHWRunning() {
        return new Promise((resolve) => {
            exec('tasklist /FI "IMAGENAME eq LibreHardwareMonitor.exe" /FO CSV /NH', (err, stdout) => {
                if (err) {
                    resolve(false);
                    return;
                }
                
                const isRunning = stdout.toLowerCase().includes('librehardwaremonitor.exe');
                resolve(isRunning);
            });
        });
    }
    
    // Проверка доступен ли Remote Web Server
    async checkLibreHWAPI() {
        return new Promise((resolve) => {
            const http = require('http');
            const req = http.get('http://localhost:8085/data.json', (res) => {
                resolve(res.statusCode === 200);
            });
            
            req.on('error', () => {
                resolve(false);
            });
            
            req.setTimeout(2000, () => {
                req.destroy();
                resolve(false);
            });
        });
    }
    
    // Перезапуск LibreHardwareMonitor
    async restartLibreHW() {
        console.log('🔄 Попытка перезапуска LibreHardwareMonitor...');
        
        return new Promise((resolve) => {
            // Сначала убиваем процесс если он завис
            exec('taskkill /F /IM LibreHardwareMonitor.exe', () => {
                // Ждём 2 секунды
                setTimeout(() => {
                    // Запускаем заново
                    const cmd = `start "" "${this.libreHWPath}"`;
                    exec(cmd, (err) => {
                        if (err) {
                            console.error('❌ Не удалось запустить LibreHardwareMonitor:', err.message);
                            resolve(false);
                        } else {
                            console.log('✅ LibreHardwareMonitor перезапущен');
                            this.libreHWRestartAttempts++;
                            resolve(true);
                        }
                    });
                }, 2000);
            });
        });
    }
    
    // Проверка работы чтения процессов
    async checkProcessDetection() {
        return new Promise((resolve) => {
            exec('tasklist /FO CSV /NH', (err, stdout) => {
                if (err || !stdout) {
                    resolve(false);
                    return;
                }
                
                // Проверяем что вывод валидный
                const isValid = stdout.includes('"') && stdout.length > 100;
                resolve(isValid);
            });
        });
    }
    
    // Проверка работы powercfg
    async checkPowerCfg() {
        return new Promise((resolve) => {
            // Пробуем несколько команд для проверки
            exec('powercfg /query', (err, stdout) => {
                if (err) {
                    // Если ошибка - пробуем альтернативную команду
                    exec('powercfg /L', (err2, stdout2) => {
                        if (err2 || !stdout2) {
                            console.log('⚠️ PowerCfg: обе команды не работают');
                            resolve(false);
                            return;
                        }
                        // Проверяем что есть вывод
                        const isValid = stdout2.length > 50;
                        if (!isValid) {
                            console.log('⚠️ PowerCfg: пустой вывод');
                        }
                        resolve(isValid);
                    });
                    return;
                }

                // Проверяем что вывод валидный (есть GUID или название схемы)
                const isValid = stdout.length > 50 && 
                    (stdout.includes('GUID') || 
                     stdout.includes('Scheme') ||
                     stdout.includes('Current'));
                
                if (!isValid) {
                    console.log('⚠️ PowerCfg: странный вывод');
                }
                
                resolve(isValid);
            });
        });
    }
    
    // Полная проверка здоровья системы
    async performHealthCheck() {
        const now = Date.now();
        if (now - this.lastCheck < this.checkInterval) {
            return { healthy: true, cached: true };
        }
        
        this.lastCheck = now;
        
        const results = {
            libreHWRunning: await this.checkLibreHWRunning(),
            libreHWAPI: await this.checkLibreHWAPI(),
            processDetection: await this.checkProcessDetection(),
            powerCfg: await this.checkPowerCfg(),
            timestamp: new Date().toISOString()
        };
        
        // Если LibreHW не запущен или API не отвечает - пробуем перезапустить
        if (!results.libreHWRunning || !results.libreHWAPI) {
            if (this.libreHWRestartAttempts < this.maxRestartAttempts) {
                console.log('⚠️ LibreHardwareMonitor не работает, пробую перезапустить...');
                const restarted = await this.restartLibreHW();
                
                if (restarted) {
                    // Ждём 5 секунд и проверяем снова
                    await new Promise(resolve => setTimeout(resolve, 5000));
                    results.libreHWRunning = await this.checkLibreHWRunning();
                    results.libreHWAPI = await this.checkLibreHWAPI();
                }
            } else {
                console.log('⚠️ Превышен лимит попыток перезапуска LibreHardwareMonitor');
            }
        } else {
            // Если всё работает - сбрасываем счётчик
            this.libreHWRestartAttempts = 0;
        }
        
        // Проверяем критичные проблемы
        const critical = [];
        if (!results.powerCfg) {
            critical.push('PowerCfg не работает - нет прав администратора?');
        }
        if (!results.processDetection) {
            critical.push('Детект процессов не работает');
        }
        
        const healthy = results.libreHWAPI && results.processDetection && results.powerCfg;
        
        if (!healthy) {
            console.log('⚠️ Проблемы со здоровьем системы:');
            if (!results.libreHWRunning) console.log('  ❌ LibreHardwareMonitor не запущен');
            if (!results.libreHWAPI) console.log('  ❌ LibreHardwareMonitor API не отвечает');
            if (!results.processDetection) console.log('  ❌ Детект процессов не работает');
            if (!results.powerCfg) console.log('  ❌ PowerCfg не работает');
        }
        
        return {
            healthy,
            results,
            critical,
            timestamp: results.timestamp
        };
    }
    
    // Получение статуса здоровья
    getHealthStatus() {
        return {
            lastCheck: this.lastCheck,
            restartAttempts: this.libreHWRestartAttempts,
            maxRestartAttempts: this.maxRestartAttempts
        };
    }
}

module.exports = new HealthCheck();
