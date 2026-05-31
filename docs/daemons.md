# KZSH Демони

## Доступные демоны

### kautostart - авто запуск приложений
```bash
kautostart add steam 'steam -silent'    # добавить
kautostart add discord 'discord'       # добавить
kautostart list                         # список
kautostart remove steam                # удалить
```

### kdaemon - управление демонами

#### termoregulator
- Мониторинг температуры CPU (`/sys/class/thermal/`)
- Управление профилями питания (`powerprofilesctl`)
- Веб интерфейс: `http://localhost:9110`

```bash
kdaemon check              # проверить зависимости
kdaemon enable termoregulator  # включить авто старт
kdaemon start termoregulator   # запустить сейчас
```

#### DMS виджет
`~/.config/dms/temp-widget.sh` - добавьте в конфиг DankMaterialShell:
```
exec = ~/.config/kzsh/public/temp-widget.sh
```

## Зависимости
- `power-profiles-daemon` - управление профилями питания
- `lm_sensors` - альтернативный метод чтения температуры