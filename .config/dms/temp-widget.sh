#!/bin/bash
# DMS Temperature Widget - серенево-чёрный стиль
# Добавьте в ваш DankMaterialShell конфиг:
# exec = script.sh

TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print int($1/1000)}')
[ -z "$TEMP" ] && TEMP="—"

PROFILE=$(powerprofilesctl get 2>/dev/null || echo "unknown")

# ANSI цвета сереневого стиля
PURPLE="\033[38;2;179;136;235m"  # #b388eb
RESET="\033[0m"

case "$PROFILE" in
    performance) echo -e "${PURPLE}🌡️ ${TEMP}°C perf${RESET}" ;;
    power-saver) echo -e "${PURPLE}🌡️ ${TEMP}°C save${RESET}" ;;
    *) echo -e "${PURPLE}🌡️ ${TEMP}°C ${PROFILE}${RESET}" ;;
esac