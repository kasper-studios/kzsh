const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const CHECKS = {
    powerprofilesctl: { cmd: 'powerprofilesctl get', name: 'Power Profiles Daemon', install: 'sudo pacman -S power-profiles-daemon' },
    sensors: { cmd: 'sensors -v', name: 'LM Sensors', install: 'sudo pacman -S lm_sensors' },
    node: { cmd: 'node -v', name: 'Node.js', install: 'sudo pacman -S nodejs npm' }
};

async function check() {
    console.log('\n═══════════════════════════════════════');
    console.log('   ПРОВЕРКА ЗАВИСИМОСТЕЙ           ');
    console.log('═══════════════════════════════════════\n');

    const results = {};
    let allOk = true;

    for (const [key, check] of Object.entries(CHECKS)) {
        await new Promise(resolve => {
            exec(check.cmd, (err) => {
                results[key] = !err;
                if (err) allOk = false;
                console.log(`${!err ? '✅' : '❌'} ${check.name}`);
                if (err) console.log(`   Установить: ${check.install}`);
                resolve();
            });
        });
    }

    console.log(allOk ? '\n✅ Все зависимости установлены\n' : '\n⚠️ Установите недостающие пакеты\n');
    return allOk;
}

check();