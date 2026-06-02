const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const CONFIG_FILE = '.demonic';

if (!fs.existsSync(CONFIG_FILE)) {
    fs.writeFileSync(CONFIG_FILE, JSON.stringify({ demons: { termoregulator: false } }, null, 2));
}

const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
const enabled = Boolean(config.demons && config.demons.termoregulator);

function commandExists(command) {
    return new Promise((resolve) => {
        exec(`command -v ${command}`, (error, stdout) => {
            resolve(!error && stdout.trim().length > 0);
        });
    });
}

function hasSysfsGovernor() {
    try {
        return fs.readdirSync('/sys/devices/system/cpu')
            .some((entry) => /^cpu\d+$/.test(entry) && fs.existsSync(`/sys/devices/system/cpu/${entry}/cpufreq/scaling_governor`));
    } catch (error) {
        return false;
    }
}

function hasSysfsTemperature() {
    try {
        return fs.readdirSync('/sys/class/hwmon')
            .some((dir) => fs.readdirSync(path.join('/sys/class/hwmon', dir)).some((file) => /^temp\d+_input$/.test(file)));
    } catch (error) {
        return false;
    }
}

async function checkLinuxCapabilities() {
    const powerBackends = [];
    if (await commandExists('powerprofilesctl')) powerBackends.push('powerprofilesctl');
    if (await commandExists('cpupower')) powerBackends.push('cpupower');
    if (hasSysfsGovernor()) powerBackends.push('sysfs-governor');
    if (fs.existsSync('/sys/devices/system/cpu/cpufreq/boost') || fs.existsSync('/sys/devices/system/cpu/intel_pstate/no_turbo')) {
        powerBackends.push('sysfs-boost');
    }

    return {
        sensors: await commandExists('sensors'),
        upower: await commandExists('upower'),
        sysfsTemperature: hasSysfsTemperature(),
        powerBackends
    };
}

(async () => {
    const caps = await checkLinuxCapabilities();

    console.log('\n═══════════════════════════════════════');
    console.log('           KZSH ДЕМОНИЧЕСКАЯ СИСТЕМА           ');
    console.log('═══════════════════════════════════════\n');

    if (!caps.sysfsTemperature && !caps.sensors) {
        console.log('⚠️ Температурные датчики не найдены. Поставь lm_sensors и выполни sensors-detect.');
    }

    if (caps.powerBackends.length === 0) {
        console.log('⚠️ Нет backend для управления питанием. Желательно: power-profiles-daemon или cpupower.');
        console.log('   Arch: sudo pacman -S power-profiles-daemon lm_sensors');
    } else {
        console.log(`⚡ Power backends: ${caps.powerBackends.join(', ')}`);
    }

    console.log(`🌡️ Termoregulator: ${enabled ? 'вкл' : 'выкл'}`);

    if (enabled) {
        console.log('🚀 Запускаю терморегулятор...\n');
        exec(`node ${path.join(__dirname, 'demons', 'termoregulator.js')}`, {
            detached: true,
            stdio: 'ignore'
        }).unref();
    }
})();