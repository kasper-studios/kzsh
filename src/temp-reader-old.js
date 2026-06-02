const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');
const http = require('http');

// Метод 0: Через LibreHardwareMonitor Remote Web Server
function getTempLibreHWRemote() {
    return new Promise((resolve) => {
        const req = http.get('http://localhost:8085/data.json', (res) => {
            let data = '';
            
            res.on('data', (chunk) => {
                data += chunk;
            });
            
            res.on('end', () => {
                try {
                    const json = JSON.parse(data);
                    // Ищем температуру CPU
                    const findTemp = (node) => {
                        if (node.Text && node.Value && 
                            (node.Text.includes('CPU Package') || 
                             node.Text.includes('Tctl/Tdie') ||
                             node.Text.includes('Core Average'))) {
                            const temp = parseFloat(node.Value.replace('°C', '').trim());
                            if (!isNaN(temp)) return temp;
                        }
                        if (node.Children) {
                            for (const child of node.Children) {
                                const temp = findTemp(child);
                                if (temp !== null) return temp;
                            }
                        }
                        return null;
                    };
                    
                    const temp = findTemp(json);
                    resolve(temp);
                } catch (e) {
                    resolve(null);
                }
            });
        });
        
        req.on('error', () => {
            resolve(null);
        });
        
        req.setTimeout(1000, () => {
            req.destroy();
            resolve(null);
        });
    });
}

// Метод 1: Через нативную утилиту (если скомпилирована)
function getTempNative() {
    return new Promise((resolve) => {
        const exePath = path.join(__dirname, 'tools', 'temp-reader.exe');
        if (!fs.existsSync(exePath)) {
            resolve(null);
            return;
        }
        
        exec(`"${exePath}"`, (err, stdout) => {
            if (err) {
                resolve(null);
                return;
            }
            const temp = parseFloat(stdout.trim());
            resolve(isNaN(temp) || temp <= 0 ? null : temp);
        });
    });
}

// Метод 2: Через WMIC (работает на большинстве систем)
function getTempWMIC() {
    return new Promise((resolve) => {
        exec('wmic /namespace:\\\\root\\wmi PATH MSAcpi_ThermalZoneTemperature get CurrentTemperature', (err, stdout) => {
            if (err || !stdout) {
                resolve(null);
                return;
            }
            
            const lines = stdout.trim().split('\n');
            if (lines.length > 1) {
                const temp = parseInt(lines[1].trim());
                if (!isNaN(temp)) {
                    // Конвертация из деци-кельвинов в цельсии
                    resolve((temp / 10) - 273.15);
                    return;
                }
            }
            resolve(null);
        });
    });
}

// Метод 3: Через PowerShell и OpenHardwareMonitor WMI
function getTempOHM() {
    return new Promise((resolve) => {
        const cmd = `powershell -Command "Get-WmiObject -Namespace root/OpenHardwareMonitor -Class Sensor -ErrorAction SilentlyContinue | Where-Object {$_.SensorType -eq 'Temperature' -and ($_.Name -match 'CPU Package' -or $_.Name -match 'Core Average' -or $_.Name -match 'Tctl')} | Select-Object -First 1 -ExpandProperty Value"`;
        
        exec(cmd, (err, stdout) => {
            if (err || !stdout.trim()) {
                resolve(null);
                return;
            }
            const temp = parseFloat(stdout.trim());
            resolve(isNaN(temp) ? null : temp);
        });
    });
}

// Метод 4: Через LibreHardwareMonitor WMI (более новая версия OHM)
function getTempLibreHW() {
    return new Promise((resolve) => {
        const cmd = `powershell -Command "Get-WmiObject -Namespace root/LibreHardwareMonitor -Class Sensor -ErrorAction SilentlyContinue | Where-Object {$_.SensorType -eq 'Temperature' -and ($_.Name -match 'CPU Package' -or $_.Name -match 'Core Average' -or $_.Name -match 'Tctl')} | Select-Object -First 1 -ExpandProperty Value"`;
        
        exec(cmd, (err, stdout) => {
            if (err || !stdout.trim()) {
                resolve(null);
                return;
            }
            const temp = parseFloat(stdout.trim());
            resolve(isNaN(temp) ? null : temp);
        });
    });
}

// Метод 5: Прямой запрос температуры через PowerShell (AMD Ryzen)
function getTempAMDDirect() {
    return new Promise((resolve) => {
        // Используем Get-Counter для чтения температуры процессора
        const cmd = `powershell -Command "$temp = (Get-Counter '\\Thermal Zone Information(*)\\Temperature' -ErrorAction SilentlyContinue).CounterSamples.CookedValue; if ($temp) { ($temp - 273.15) } else { 0 }"`;
        
        exec(cmd, (err, stdout) => {
            if (err || !stdout.trim()) {
                resolve(null);
                return;
            }
            const temp = parseFloat(stdout.trim());
            resolve(isNaN(temp) || temp <= 0 ? null : temp);
        });
    });
}

let lastTemp = 0;
let methodUsed = 'none';

// Пробуем все методы по очереди
async function getCpuTemperature() {
    // 0. LibreHardwareMonitor Remote Web Server (если запущен)
    let temp = await getTempLibreHWRemote();
    if (temp !== null && temp > 0) {
        if (methodUsed !== 'librehw-remote') {
            console.log(`✓ Температура через LibreHardwareMonitor Remote: ${temp}°C`);
            methodUsed = 'librehw-remote';
        }
        lastTemp = temp;
        return temp;
    }
    
    // 1. Нативная утилита (если есть)
    temp = await getTempNative();
    if (temp !== null && temp > 0) {
        if (methodUsed !== 'native') {
            console.log(`✓ Температура через нативную утилиту: ${temp}°C`);
            methodUsed = 'native';
        }
        lastTemp = temp;
        return temp;
    }
    
    // 2. OpenHardwareMonitor (если запущен)
    temp = await getTempOHM();
    if (temp !== null && temp > 0) {
        if (methodUsed !== 'ohm') {
            console.log(`✓ Температура через OpenHardwareMonitor: ${temp}°C`);
            methodUsed = 'ohm';
        }
        lastTemp = temp;
        return temp;
    }
    
    // 3. LibreHardwareMonitor WMI (если запущен)
    temp = await getTempLibreHW();
    if (temp !== null && temp > 0) {
        if (methodUsed !== 'librehw') {
            console.log(`✓ Температура через LibreHardwareMonitor WMI: ${temp}°C`);
            methodUsed = 'librehw';
        }
        lastTemp = temp;
        return temp;
    }
    
    // 4. WMIC
    temp = await getTempWMIC();
    if (temp !== null && temp > 0) {
        if (methodUsed !== 'wmic') {
            console.log(`✓ Температура через WMIC: ${temp}°C`);
            methodUsed = 'wmic';
        }
        lastTemp = temp;
        return temp;
    }
    
    // 5. AMD Direct
    temp = await getTempAMDDirect();
    if (temp !== null && temp > 0) {
        if (methodUsed !== 'amd') {
            console.log(`✓ Температура через AMD Direct: ${temp}°C`);
            methodUsed = 'amd';
        }
        lastTemp = temp;
        return temp;
    }
    
    if (methodUsed !== 'none') {
        console.log('⚠ Не удалось получить температуру. Запусти LibreHardwareMonitor с Remote Web Server на порту 8085');
        methodUsed = 'none';
    }
    
    return lastTemp; // Возвращаем последнее известное значение
}

module.exports = { getCpuTemperature };
