const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

function execOk(command) {
    return new Promise((resolve) => {
        exec(command, { encoding: 'utf8', timeout: 3000 }, (error, stdout = '') => {
            resolve({ ok: !error, stdout: stdout.trim() });
        });
    });
}

async function commandExists(command) {
    const result = await execOk(`command -v ${command}`);
    return result.ok && result.stdout.length > 0;
}

function hasSysfsTemperature() {
    try {
        return fs.readdirSync('/sys/class/hwmon')
            .some((dir) => fs.readdirSync(path.join('/sys/class/hwmon', dir)).some((file) => /^temp\d+_input$/.test(file)));
    } catch (error) {
        return false;
    }
}

function hasSysfsGovernor() {
    try {
        return fs.readdirSync('/sys/devices/system/cpu')
            .some((entry) => /^cpu\d+$/.test(entry) && fs.existsSync(`/sys/devices/system/cpu/${entry}/cpufreq/scaling_governor`));
    } catch (error) {
        return false;
    }
}

function hasSysfsBoost() {
    return fs.existsSync('/sys/devices/system/cpu/cpufreq/boost') ||
        fs.existsSync('/sys/devices/system/cpu/intel_pstate/no_turbo');
}

async function check() {
    console.log('\n═══════════════════════════════════════');
    console.log('   ПРОВЕРКА KZSH ТЕРМОРЕГУЛЯТОРА      ');
    console.log('═══════════════════════════════════════\n');

    const node = await execOk('node -v');
    const sensors = await commandExists('sensors');
    const upower = await commandExists('upower');
    const powerprofilesctl = await commandExists('powerprofilesctl');
    const cpupower = await commandExists('cpupower');
    const sysfsTemperature = hasSysfsTemperature();
    const sysfsGovernor = hasSysfsGovernor();
    const sysfsBoost = hasSysfsBoost();

    const tempOk = sysfsTemperature || sensors;
    const powerOk = powerprofilesctl || cpupower || sysfsGovernor || sysfsBoost;

    console.log(`${node.ok ? '✅' : '❌'} Node.js ${node.stdout || ''}`);
    console.log(`${tempOk ? '✅' : '❌'} Температура CPU (${sysfsTemperature ? 'sysfs' : sensors ? 'lm_sensors' : 'не найдено'})`);
    console.log(`${powerOk ? '✅' : '❌'} Управление питанием (${[
        powerprofilesctl && 'powerprofilesctl',
        cpupower && 'cpupower',
        sysfsGovernor && 'sysfs-governor',
        sysfsBoost && 'sysfs-boost'
    ].filter(Boolean).join(', ') || 'не найдено'})`);
    console.log(`${upower ? '✅' : '⚠️'} UPower ${upower ? '' : '(не критично, есть sysfs fallback)'}`);
    console.log(`${sensors ? '✅' : '⚠️'} lm_sensors ${sensors ? '' : '(не критично, если sysfs датчики есть)'}`);

    if (!tempOk) {
        console.log('\n   Установить/настроить: sudo pacman -S lm_sensors && sudo sensors-detect');
    }
    if (!powerOk) {
        console.log('   Установить: sudo pacman -S power-profiles-daemon или sudo pacman -S cpupower');
    }

    const allOk = node.ok && tempOk && powerOk;
    console.log(allOk ? '\n✅ Терморегулятор готов к работе\n' : '\n⚠️ Есть проблемы, но часть функций может работать через fallback\n');
    return allOk;
}

check();