#!/bin/bash
# 容器啟動時自動還原資料庫（由官方 entrypoint 執行 /var/custom/ 下的腳本觸發）。
#
# 還原來源是 /database/backups/{database}/ 這個結構化目錄，對應宿主機的 ./backups/。
# 優先順序：
#   1. 若環境變數 RESTORE_DB 有值，只還原該資料庫
#   2. 否則掃描 /database/backups/*/ 下的所有備份目錄，依序還原
# 若資料庫已存在則跳過，不會覆蓋既有資料。
set -euo pipefail

BACKUP_ROOT="/database/backups"
INSTANCE_USER="db2inst1"

echo "==> 正在偵測還原環境..."

# 等待 db2inst1 使用者出現 (有時候腳本執行太快，使用者還沒建立好)
timeout=60
while ! id "$INSTANCE_USER" &>/dev/null; do
    echo "==> 等待 $INSTANCE_USER 使用者建立中..."
    sleep 5
    ((timeout -= 5))
    if [ $timeout -le 0 ]; then
        echo "==> [錯誤] 等待 $INSTANCE_USER 使用者超時"
        exit 1
    fi
done

echo "==> 等待 DB2 實例就緒..."
until su - "$INSTANCE_USER" -c "db2 get snapshot for dbm" &>/dev/null; do
    sleep 5
done
echo "==> DB2 實例已就緒。"

restore_database() {
    local DB_NAME=$1
    local BACKUP_DIR=$2

    echo "----------------------------------------------------"
    echo "目標資料庫：$DB_NAME"
    echo "備份目錄：$BACKUP_DIR"

    # 先確認備份檔存在，再決定要不要動現有的資料庫。
    # 順序不能反過來：早期版本是先 drop 空資料庫、後找備份檔，只要 backups/{db}/
    # 底下沒有備份檔（例如只留了 metadata.json），entrypoint 剛建好的空資料庫就會
    # 被砍掉又還原不回來，容器最後停在「一個資料庫都沒有」的狀態。
    #
    # 挑出要用的備份檔：DB2 的檔名格式是 {來源DB}.0.{實例}.DBPART000.{時間戳}.001
    shopt -s nullglob
    local FILES=("$BACKUP_DIR"/*.DBPART*.[0-9][0-9][0-9])
    if [ ${#FILES[@]} -eq 0 ]; then
        echo "[略過] $BACKUP_DIR 下找不到 DB2 備份檔，保留現有資料庫不動。"
        return
    fi

    # 檔名裡的第 5 段是備份時間戳，排序後取最新的一份
    local BACKUP_FILE
    BACKUP_FILE=$(printf '%s\n' "${FILES[@]}" | sort -t. -k5,5 | tail -1)
    local SOURCE_DB TIMESTAMP
    SOURCE_DB=$(basename "$BACKUP_FILE" | cut -d'.' -f1)
    TIMESTAMP=$(basename "$BACKUP_FILE" | cut -d'.' -f5)

    if su - "$INSTANCE_USER" -c "db2 list db directory" | grep -qiw "$DB_NAME"; then
        # 官方 entrypoint 會依 DBNAME 先建一個空的資料庫，那不算「既有資料」。
        # 只有真的含使用者資料表時才跳過，避免覆蓋別人的東西。
        local TABLE_COUNT
        TABLE_COUNT=$(su - "$INSTANCE_USER" -c \
            "db2 connect to $DB_NAME >/dev/null && db2 -x \"SELECT COUNT(*) FROM SYSCAT.TABLES WHERE TABSCHEMA NOT LIKE 'SYS%' AND OWNERTYPE='U' AND TYPE='T'\"; db2 connect reset >/dev/null" \
            | tr -dc '0-9')
        TABLE_COUNT=${TABLE_COUNT:-0}

        if [ "$TABLE_COUNT" -gt 0 ]; then
            echo "[跳過] 資料庫 '$DB_NAME' 已存在且含有 $TABLE_COUNT 張使用者資料表。"
            return
        fi

        echo "[清理] 資料庫 '$DB_NAME' 是空的（entrypoint 自動建立的），先移除再從備份還原。"
        su - "$INSTANCE_USER" -c "db2 force applications all >/dev/null 2>&1 || true; sleep 3; db2 drop database $DB_NAME"
    fi

    echo "備份檔：$(basename "$BACKUP_FILE")"
    echo "[開始] 正在從備份還原 '$SOURCE_DB' -> '$DB_NAME'..."

    su - "$INSTANCE_USER" -c \
        "db2 restore database $SOURCE_DB from $BACKUP_DIR taken at $TIMESTAMP into $DB_NAME without prompting"

    # 還原成不同名稱時 DB2 會進入 ROLL-FORWARD PENDING，必須收尾才連得上
    su - "$INSTANCE_USER" -c "db2 rollforward database $DB_NAME to end of backup and complete" || true

    echo "[成功] '$DB_NAME' 還原完成。"
}

if [ -n "${RESTORE_DB:-}" ]; then
    echo "==> 指定還原單一資料庫：$RESTORE_DB"
    if [ -d "$BACKUP_ROOT/$RESTORE_DB" ]; then
        restore_database "$RESTORE_DB" "$BACKUP_ROOT/$RESTORE_DB"
    else
        echo "==> [錯誤] 找不到資料庫 $RESTORE_DB 的備份目錄 $BACKUP_ROOT/$RESTORE_DB。"
    fi
else
    echo "==> 掃描所有備份目錄進行還原..."
    shopt -s nullglob
    found_any=false

    for dir in "$BACKUP_ROOT"/*/; do
        DB=$(basename "$dir")
        restore_database "$DB" "${dir%/}"
        found_any=true
    done

    if [ "$found_any" = false ]; then
        echo "==> [警告] 在 $BACKUP_ROOT 下找不到任何備份目錄。"
    fi
fi

echo "==> 所有還原程序結束。"
