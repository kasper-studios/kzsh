const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const CONFIG_FILE = '.demonic';

if (!fs.existsSync(CONFIG_FILE)) {
    fs.writeFileSync(CONFIG_FILE, JSON.stringify({ demons: { termoregulator: false } }, null, 2);
}

const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
const enabled = config.demons.termoregulator;

const checks = {
    'powerprofilesctl': 'powerprofilesctl get',
    'sensors': 'sensors 2>/dev/null'
};

async function checkDeps() {
    const missing = [];
    for (const [cmd, checkCmd] of Object.entries(checks)) {
        await new Promise(r => exec(`which ${cmd}`, (e) => { if (e) missing.push(cmd); r(); }));
    }
    return missing;
}

(async () => {
    const missing = await checkDeps();
    
    console.log('\n═══════════════════════════════════════');
    console.log('           KZSH ДЕМОНИЧЕСКАЯ СИСТЕМА           ');
    console.log('═══════════════════════════════════════\n');
    
    if (missing.length > 0) {
        console.log('❌ Отсутствуют команды:', missing.join(', '));
        console.log('   Установить: sudo pacman -S power-profiles-daemon lm_sensors\n');
    }
    
    console.log(`🌡️ Termoregulator: ${enabled ? 'вкл' : 'выкл'}`);
    
    if (enabled && missing.length === 0) {
        console.log('🚀 Запускаю терморегулятор...\n');
        exec(`node ${path.join(__dirname, 'demons', 'termoregulator.js')}`, {
            detached: true,
            stdio: 'ignore'
        }).unref();
    }
})();