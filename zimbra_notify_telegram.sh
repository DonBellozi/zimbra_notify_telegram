#!/bin/bash
# delete_old_accounts.sh - Автоматическая очистка старых почтовых ящиков Zimbra
#
# Copyright (c) 2025 Ivan V. Belikov
#
# Лицензия: MIT License (см. файл LICENSE)
# https://opensource.org/licenses/MIT
# ------------------------------------------------------------


export PATH="/usr/bin:/bin"
export LANG="ru_RU.UTF-8"
export LC_ALL="ru_RU.UTF-8"

# Замените на актуальные данные вашего Telegram-бота:

BOT_TOKEN="123456789:AA...xyz"
# Токен бота, созданного через @BotFather

CHAT_ID="-1001234567890"
# ID Telegram-группы или пользователя, полученный через @getmyid_bot
# Для групповых чатов ID начинается с -100

LOG_FILE="/opt/zimbra/logs/zimbra_disable_today.log"
DEL_FILE="/opt/zimbra/logs/deleted_accounts_report.log"
DEBUG_LOG="/opt/zimbra/logs/cron_telegram_debug.log"

MAX_LINES_PER_MESSAGE=50
echo "[$(date)] Запуск скрипта уведомления в Telegram" >> "$DEBUG_LOG"

# --- Считываем данные ---
mapfile -t disable_lines < <(grep -v '^\s*$' "$LOG_FILE" 2>/dev/null)
mapfile -t delete_raw < <(grep -v '^\s*$' "$DEL_FILE" 2>/dev/null)

delete_lines=()
for line in "${delete_raw[@]}"; do
    IFS=";" read -r email date <<< "$line"
    [[ -n "$email" && "$email" != "Email" ]] && delete_lines+=("${email} (удалено: ${date})")
done

total_lines=("${disable_lines[@]}" "${delete_lines[@]}")

# --- Создание чанков по 50 строк ---
total_count=${#total_lines[@]}
chunks=$(( (total_count + MAX_LINES_PER_MESSAGE - 1) / MAX_LINES_PER_MESSAGE ))
success=true
start=0

for ((i=0; i<chunks; i++)); do
    message=""
    has_disable=false
    has_delete=false
    end=$((start + MAX_LINES_PER_MESSAGE))
    [[ $end -gt $total_count ]] && end=$total_count

    # Выделение текущего чанка
    for ((j=start; j<end; j++)); do
        line="${total_lines[j]}"
        # Определим тип строки по наличию в оригинальном массиве
        if [[ " ${disable_lines[*]} " == *" ${line} "* ]]; then
            [[ $has_disable == false ]] && message+="*Отключены следующие учётные записи Zimbra за сегодня:*\n\n" && has_disable=true
        elif [[ " ${delete_lines[*]} " == *" ${line} "* ]]; then
            [[ $has_delete == false ]] && message+="*Удалены следующие учётные записи по сроку давности (не используются более одного (1) года):*\n\n" && has_delete=true
        fi

	# Экранируем спецсимволы Markdown в данных (email/тексте)
	safe_line="$line"
	safe_line="${safe_line//\\/\\\\}"   # сначала экранируем обратный слэш
	safe_line="${safe_line//_/\\_}"
	safe_line="${safe_line//\*/\\*}"   # ВАЖНО: именно \* в pattern
	safe_line="${safe_line//\[/\\[}"
	safe_line="${safe_line//\]/\\]}"
	safe_line="${safe_line//\`/\\\`}"

	message+="$safe_line\n"
    done

    # Отправка чанка
    response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        --data-urlencode text="$(echo -e "$message")" \
        -d parse_mode="Markdown")

    echo "[$(date)] Ответ Telegram (chunk $((i+1))): $response" >> "$DEBUG_LOG"

    if ! echo "$response" | grep -q '"ok":true'; then
        echo "[$(date)] Ошибка при отправке чанка $((i+1))" >> "$DEBUG_LOG"
        success=false
        break
    fi

    start=$end

    # Пауза между сообщениями
    sleep 5
done

# --- Очистка логов при успехе ---
if $success; then
    echo "[$(date)] Все сообщения отправлены успешно. Очищаем логи." >> "$DEBUG_LOG"
    > "$LOG_FILE"
    > "$DEL_FILE"
else
    echo "[$(date)] Ошибка при отправке сообщений. Логи не очищены." >> "$DEBUG_LOG"
fi
