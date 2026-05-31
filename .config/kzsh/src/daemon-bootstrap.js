const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const dir = __dirname;

async function checkRuntime() {
    return new Promise((resolve) => {
        exec('which node bun', (err, stdout) => {
            const hasNode = stdout.includes('node');
            const hasBun = stdout.includes('bun');
            resolve({ hasNode, hasBun });
        });
    });
}

async function checkSystemDeps() {
    return new Promise((resolve) => {
        exec('which powerprofilesctl sensors', (err) => {
            resolve(!err);
        });
    });
}

async function bootstrap() {
    const { hasNode, hasBun } = await checkRuntime();
    
    if (!hasNode && !hasBun) {
        console.log('❌ Node.js или Bun не установлены!');
        console.log('   Установите: sudo pacman -S nodejs npm OR curl -fsSL https://bun.sh/install | bash');
        process.exit(1);
    }
    
    const runner = hasBun ? 'bun' : 'node';
    
    console.log('📦 Проверка системных зависимостей...');
    const systemOk = await checkSystemDeps();
    
    if (!systemOk) {
        console.log('❌ Отсутствуют зависимости: power-profiles-daemon lm_sensors');
        console.log('   Установите: sudo pacman -S power-profiles-daemon lm_sensors');
        process.exit(1);
    }
    
    console.log(`✅ Все зависимости готовы (runner: ${runner})`);
    return runner;
}

module.exports = { bootstrap, checkSystemDeps, checkRuntime };