# DB2 Podman 故障排除

先查看容器狀態與日誌：

```bash
podman ps -a
podman-compose logs -f
podman logs --tail 100 db2-gtky
```

## 資料持久化與 rootless Podman

DB2 的實例、資料及交易日誌存放在具名 volume `db2_data`，Compose 專案預設建立的實際名稱是 `db2-podman_db2_data`。刪除容器或執行 `podman-compose down` 不會預設刪除它。

早期將 `./db2_storage` bind mount 到 `/database` 時，rootless Podman 的 UID/GID 映射造成 DB2 所需的檔案擁有者不符，實例建立失敗：

```text
DBI20187E The fencedid file ".../sqllib/adm/fencedid"
is invalid because it is not owned by the "root":"db2iadm1".
```

bind mount 也會固定來源的絕對路徑。專案目錄改名後，舊容器可能仍指向舊路徑，表現得像資料庫消失。遇到這兩種情況，請檢查 `docker-compose.yml` 中 `/database` 是否仍使用具名 volume，而非專案目錄。

## `/database` 掛載權限

DB2 啟動時需要 `sqllib/adm/` 中的特殊權限執行檔。掛載選項不合適時可能看到：

```text
(*) Remounting /database with suid...
mount: /database: permission denied.
SQL1042C An unexpected system error occurred.
```

目前 `docker-compose.yml` 使用 `db2_data:/database:suid,dev,exec`，並設定 `PERSIST_CONFIG=false`。調整掛載或持久化設定後，應重新驗證 DB2 初始化與連線。

## 資料庫沒有還原

還原腳本只在容器初始化流程執行。請先檢查 `backups/PTPMSDB/` 是否有真正的 DB2 備份檔；`metadata.json` 本身不足以還原。腳本會挑選最新備份；若目標資料庫已有使用者資料表，就會跳過。首次啟動由 entrypoint 建立的空資料庫則可能先被移除，再從備份還原。還原失敗時，腳本會嘗試建立空資料庫作為後備。

如果要指定資料庫，請在建立或重新建立容器時設定環境變數：

```bash
RESTORE_DB=PTPMSDB podman-compose up -d
```

`RESTORE_DB` 限制要處理的備份目錄，不會覆蓋已有使用者資料表的資料庫。對已在執行的容器設定 Shell 變數，也不會讓腳本立刻執行。完整重建見 [備份與還原規範](../BACKUP.md)。

## 常見錯誤

| 錯誤或現象 | 可能原因 | 處理方向 |
| --- | --- | --- |
| `SQL1024N` | 尚未連線資料庫 | 執行 `db2 connect` |
| `SQL1001N` | 資料庫名稱無效，或互動模式誤加分號 | 檢查名稱與指令格式 |
| `SQL1042C` | DB2 啟動異常，可能與掛載權限有關 | 檢查 Compose 設定及日誌 |
| `SQL2040N` | 資料庫名稱超過 8 個字元 | 縮短 `backups/` 目錄名稱 |
| `DBI20187E` | 實例檔案擁有者不符 | 檢查 UID/GID 映射與 volume |
| 查不到資料表 | Schema 不正確，或還原的備份沒有表 | 查 `CURRENT SCHEMA` 與還原日誌 |
| 重建容器後資料仍存在 | 具名 volume 仍存在 | 依 [完整重建流程](../BACKUP.md#完整重建) 處理 |

備份目錄名稱會成為目標資料庫名稱，最多 8 個字元；例如 `PTPMSDB` 有效，`PTPMSDATABASE` 過長。
