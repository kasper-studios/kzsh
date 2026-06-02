const tempReader = require('../core/temperature');
const powerManager = require('../core/power');

console.log('🔥 Termoregulator daemon started');

setInterval(async () => {
    try {
        const temp = await tempReader.getCpuTemperature();
        console.log(`🌡️ Current temp: ${temp}°C`);
        
        if (temp > 85) {
            console.log('⚠️ High temp, setting powersave');
            await powerManager.setPowerMode(false);
        } else if (temp < 60) {
            console.log('✅ Normal temp, setting performance');
            await powerManager.setPowerMode(true);
        }
    } catch (e) {
        console.error('Daemon error:', e);
    }
}, 5000);
