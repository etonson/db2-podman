# DB2 Podman 開發環境

使用 Podman 執行 IBM Db2 Community Edition，供 GTKY 專案在本機開發與測試。資料庫名稱和應用程式帳號參照 WebSphere Liberty 的 `server-db2.xml`。

## 快速開始

在專案根目錄執行：

```bash
podman-compose up -d --build
podman-compose logs -f
```

首次啟動可能較久；日誌出現 `Setup has completed` 後再連線。Compose 設定檔是 `docker-compose.yml`，`podman-compose` 會使用它。

| 項目 | 值 |
| --- | --- |
| Host / Port | `localhost:50000` |
| Database | `PTPMSDB` |
| 應用程式帳號 | `ptpmsap` / `A@t123456` |
| 實例管理者 | `db2inst1` / `A@t123456` |
| 容器名稱 | `db2-gtky` |

`.env` 已包含本機開發設定與密碼，並納入版本控制。請勿將這組密碼用於正式環境。

進入容器並連線：

```bash
podman exec -it db2-gtky su - db2inst1
db2 connect to PTPMSDB user ptpmsap using 'A@t123456'
db2 set schema PTPMSAP
db2 "SELECT CURRENT SERVER FROM SYSIBM.SYSDUMMY1"
```

## 日常操作

```bash
podman-compose up -d                 # 啟動
podman-compose stop                  # 停止
podman-compose restart               # 重新啟動
podman-compose down                  # 移除容器，保留具名 volume
podman-compose logs -f               # 即時日誌
podman logs --tail 100 db2-gtky      # 最近 100 行日誌
```

以下 DB2 指令在進入容器、連線資料庫後執行：

```bash
db2 values current schema
db2 set schema PTPMSAP
db2 list tables for schema PTPMSAP
db2 describe table PTPMSAP.COMMON_CODE
db2 "SELECT * FROM PTPMSAP.COMMON_CODE FETCH FIRST 10 ROWS ONLY"
db2 terminate
```

`LIST TABLES` 有自己的預設列示範圍；要看指定 Schema，請明確加上 `FOR SCHEMA PTPMSAP`。其他查詢、SQL 檔案及互動模式見 [DB2 CLI 操作](docs/DB2-CLI.md)。

## 資料與備份

| 路徑 | 用途 | 版本控制 |
| --- | --- | --- |
| `.env` | 本機開發環境變數 | 是 |
| `custom/` | 容器啟動時執行的還原與帳號腳本 | 是 |
| `backups/{database}/` | 備份檔與 `metadata.json`；掛載至容器 `/database/backups` | 僅 `metadata.json` |
| `db2_data` | DB2 實例、資料與日誌的 Podman 具名 volume | 否 |

容器刪除後，具名 volume 仍保留資料庫。備份檔不進版控；新環境需要自行取得實際備份檔，單靠 `metadata.json` 無法還原。

建立離線備份前，先確認沒有應用程式使用資料庫；腳本會中斷連線：

```bash
./backup.sh              # 互動式選擇資料庫
./backup.sh PTPMSDB      # 備份指定資料庫
```

初始化時，`custom/restore-databases.sh` 會從 `backups/{database}/` 選取最新備份。沒有備份檔時會保留或建立空資料庫；已有使用者資料表時會跳過，避免覆蓋。詳細操作與完整重建步驟見 [備份與還原規範](BACKUP.md)。

## Schema 變更

`gtky-db2migrator` 是獨立的 Liquibase 工具。現有備份的中繼資料記載 `PTPMSAP` Schema 的 35 張資料表、沒有資料列；取得實際備份檔並還原後，通常不需再執行遷移。需要更新 Schema 時：

```bash
cd ../gtky-db2migrator/db2-migrator
./sync-to-db.sh
```

## 文件索引

- [DB2 CLI 操作](docs/DB2-CLI.md)：Schema、資料表、SQL 與互動模式。
- [備份與還原規範](BACKUP.md)：離線備份、自動還原與完整重建。
- [故障排除](docs/TROUBLESHOOTING.md)：rootless Podman、掛載權限與常見錯誤。
