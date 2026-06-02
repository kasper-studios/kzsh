const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');
const http = require('http');

class TemperatureReader {
    constructor() {
        this.lastTemp = 0;
        this.methodUsed = 'none';
    }
    
    // Метод 0: Через LibreHardwareMonitor Remote Web Server
    getTempLibreHWRemote() {
        return new Promise((resolve) => {
            const req = http.get('http://localhost:8085/data.json', (res) => {
                let data = '';
                
                res.on('data', (chunk) => {
                    data += chunk;
                });
                
                res.on('end', () => {
                    try {
                        const json = JSON.parse(data);
                        const temp = this.findTempInNode(json);
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
    
    findTempInNode(node) {
        if (node.Text && node.Value && 
            (node.Text.includes('CPU Package') || 
             node.Text.includes('Tctl/Tdie') ||
             node.Text.includes('Core Average'))) {
            const temp = parseFloat(node.Value.replace('°C', '').trim());
            if (!isNaN(temp)) return temp;
        }
        if (node.Children) {
            for (const child of node.Children) {
                const temp = this.findTempInNode(child);
                if (temp !== null) return temp;
            }
        }
        return null;
    }
    
    // Метод 1: Через нативную утилиту
    getTempNative() {
        return new Promise((resolve) => {
            const exePath = path.join(__dirname, '..', '..', 'tools', 'temp-reader.exe');
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
    
    // Метод 2: Через WMIC
    getTempWMIC() {
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
    
    // Метод 3: Через OpenHardwareMonitor WMI
    getTempOHM() {
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
    
    // Метод 4: Через LibreHardwareMonitor WMI
    getTempLibreHW() {
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
    
    // Метод 5: AMD Direct
    getTempAMDDirect() {
        return new Promise((resolve) => {
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
    
    // Пробуем все методы по очереди
    async getCpuTemperature() {
        // 0. LibreHardwareMonitor Remote Web Server
        let temp = await this.getTempLibreHWRemote();
        if (temp !== null && temp > 0) {
            if (this.methodUsed !== 'librehw-remote') {
                console.log(`✓ Температура через LibreHardwareMonitor Remote: ${temp}°C`);
                this.methodUsed = 'librehw-remote';
            }
            this.lastTemp = temp;
            return temp;
        }
        
        // 1. Нативная утилита
        temp = await this.getTempNative();
        if (temp !== null && temp > 0) {
            if (this.methodUsed !== 'native') {
                console.log(`✓ Температура через нативную утилиту: ${temp}°C`);
                this.methodUsed = 'native';
            }
            this.lastTemp = temp;
            return temp;
        }
        
        // 2. OpenHardwareMonitor
        temp = await this.getTempOHM();
        if (temp !== null && temp > 0) {
            if (this.methodUsed !== 'ohm') {
                console.log(`✓ Температура через OpenHardwareMonitor: ${temp}°C`);
                this.methodUsed = 'ohm';
            }
            this.lastTemp = temp;
            return temp;
        }
        
        // 3. LibreHardwareMonitor WMI
        temp = await this.getTempLibreHW();
        if (temp !== null && temp > 0) {
            if (this.methodUsed !== 'librehw') {
                console.log(`✓ Температура через LibreHardwareMonitor WMI: ${temp}°C`);
                this.methodUsed = 'librehw';
            }
            this.lastTemp = temp;
            return temp;
        }
        
        // 4. WMIC
        temp = await this.getTempWMIC();
        if (temp !== null && temp > 0) {
            if (this.methodUsed !== 'wmic') {
                console.log(`✓ Температура через WMIC: ${temp}°C`);
                this.methodUsed = 'wmic';
            }
            this.lastTemp = temp;
            return temp;
        }
        
        // 5. AMD Direct
        temp = await this.getTempAMDDirect();
        if (temp !== null && temp > 0) {
            if (this.methodUsed !== 'amd') {
                console.log(`✓ Температура через AMD Direct: ${temp}°C`);
                this.methodUsed = 'amd';
            }
            this.lastTemp = temp;
            return temp;
        }
        
        if (this.methodUsed !== 'none') {
            console.log('⚠ Не удалось получить температуру. Запусти LibreHardwareMonitor с Remote Web Server на порту 8085');
            this.methodUsed = 'none';
        }
        
        return this.lastTemp; // Возвращаем последнее известное значение
    }
}

module.exports = new TemperatureReader();
