const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const CONFIG_FILE = '.autostart';

class AutoStartDaemon {
    constructor() {
        this.apps = [];
        this.loadConfig();
    }

    loadConfig() {
        const configPath = path.join(__dirname, CONFIG_FILE);
        if (fs.existsSync(configPath)) {
            try {
                const data = JSON.parse(fs.readFileSync(configPath, 'utf8'));
                this.apps = data.apps || [];
            } catch (e) {}
        }
    }

    saveConfig() {
        const configPath = path.join(__dirname, CONFIG_FILE);
        fs.writeFileSync(configPath, JSON.stringify({ apps: this.apps }, null, 2));
    }

    addApp(name, cmd, enabled = true) {
        this.apps.push({ name, cmd, enabled });
        this.saveConfig();
        return this.apps.length - 1;
    }

    removeApp(index) {
        this.apps.splice(index, 1);
        this.saveConfig();
    }

    async startApps() {
        console.log('\n═══════════════════════════════════════');
        console.log('       АВТОЗАПУСК ПРИЛОЖЕНИЙ          ');
        console.log('═══════════════════════════════════════\n');
        
        for (const app of this.apps) {
            if (app.enabled) {
                console.log(`🚀 ${app.name}...`);
                try {
                    exec(app.cmd, { detached: true, stdio: 'ignore' });
                } catch (e) {
                    console.log(`❌ Не удалось запустить ${app.name}`);
                }
            }
        }
    }
}

module.exports = new AutoStartDaemon();