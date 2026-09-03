#!/bin/bash
# 建立應用程式使用者 (對應 server-db2.xml 的 user="ptpmsap")。
# DB2 用作業系統帳號做認證，所以要先建 OS user，再在資料庫裡授權。
set -euo pipefail

APP_USER="${APP_USER:-ptpmsap}"
APP_PASSWORD="${APP_PASSWORD:-${DB2INST1_PASSWORD:-}}"
DB_NAME="${DBNAME:-PTPMSDB}"

if [ -z "$APP_PASSWORD" ]; then
    echo "[App User] 未設定 APP_PASSWORD，略過建立 $APP_USER"
    exit 0
fi

echo "[App User] 準備建立使用者 $APP_USER"

# ---------- 建立 / 更新 OS 帳號 ----------
if ! id "$APP_USER" &>/dev/null; then
    useradd -m -g db2iadm1 "$APP_USER"
    echo "[App User] 已建立 OS 帳號 $APP_USER"
fi
echo "$APP_USER:$APP_PASSWORD" | chpasswd

# ---------- 等待 DB2 實例就緒 ----------
echo "[App User] 等待 DB2 實例就緒..."
until su - db2inst1 -c "db2 get snapshot for dbm" &>/dev/null; do
    sleep 5
done

# ---------- 授權 ----------
# 只負責授權；schema 與資料表由 gtky-db2migrator (Liquibase) 建立，
# 這裡先建會讓 migrator 的 CREATE SCHEMA 撞名失敗
su - db2inst1 -c "db2 connect to $DB_NAME && \
    db2 \"GRANT DBADM WITH DATAACCESS WITH ACCESSCTRL ON DATABASE TO USER ${APP_USER^^}\" ; \
    db2 connect reset" || true

echo "[App User] $APP_USER 設定完成"
