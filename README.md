# DB2 Podman Setup

本機用 Podman 跑 DB2 社群版 (Community Edition)。連線參數以正式環境的
WebSphere Liberty 設定 `server-db2.xml` 為準：資料庫 `PTPMSDB`、應用程式帳號 `ptpmsap`。

## 快速開始

```bash
podman-compose up -d --build
podman-compose logs -f          # 等到出現 Setup has completed
```

`.env` 已含開發環境用的設定，可直接使用；密碼僅供本機開發，故一併進版控。

## 連線資訊

| 項目 | 值 |
| --- | --- |
| Host / Port | `localhost:50000` |
| Database | `PTPMSDB` |
| 應用程式帳號 | `ptpmsap` / `A@t123456` |
| 實例管理者 | `db2inst1` / `A@t123456` |
| 容器名稱 | `db2-gtky` |

## 目錄

| 路徑 | 說明 | 進版控 |
| --- | --- | --- |
| `backups/{database}/` | 資料庫備份檔與 `metadata.json`，掛載成容器的 `/database/backups` | 只有 `metadata.json` |
| `db2_storage/` | DB2 自己產生的實例、資料與日誌，掛載成 `/database` | 否 |
| `custom/` | 開機時自動執行的初始化腳本（還原資料庫、建帳號），會複製到 `/var/custom/` | 是 |

## 常用指令

### 進入容器
```bash
podman exec -it db2-gtky su - db2inst1
db2 connect to PTPMSDB user ptpmsap using 'A@t123456'
```

### 備份與還原
詳細規範見 [BACKUP.md](BACKUP.md)。常用的是：

```bash
./backup.sh                 # 互動式選單，列出容器內所有資料庫供選擇
./backup.sh PTPMSDB         # 直接備份指定的資料庫
```

還原是**容器啟動時自動做的**：把備份放進 `backups/{database}/`，
清掉 `db2_storage/` 後重建容器，`custom/restore-databases.sh` 就會掃描並還原。
資料庫已存在則跳過，不會覆蓋既有資料。要只還原其中一個：

```bash
RESTORE_DB=PTPMSDB podman-compose up -d
```

## 關於 gtky-db2migrator

隔壁的 `gtky-db2migrator` 是**獨立的外部工具**（Liquibase），不屬於本專案的啟動流程。

當初 `backups/` 裡只有一份空的備份、沒有任何資料表，才用它把
`server-db2.xml` 對應的那套 schema（`PTPMSAP` 底下 35 張表）建進資料庫。
現在 `backups/PTPMSDB/` 的備份已經含有完整結構，**平常重建環境只要靠還原即可**，
不需要再跑 migrator。日後 schema 有變更時才會再用到它：

```bash
cd ../gtky-db2migrator/db2-migrator && ./sync-to-db.sh
```

## 已知問題

### 容器啟動後立刻 exit 1
log 出現：

```
DBI20187E  The fencedid file ".../sqllib/adm/fencedid" is invalid because it is
not owned by the "root":"db2iadm1".
```

rootless podman 的 uid 映射會讓 `fencedid` 在容器內變成 `root:root`，
`db2icrt` 因此拒絕建立實例。修法：

```bash
podman unshare chown 0:1000 db2_storage/config/db2inst1/sqllib/adm/fencedid
```

### 搬動或改名專案目錄後要重建容器
bind mount 的來源路徑是在建立容器時就寫死的。目錄改名後容器還能跑（inode 沒變），
但一旦 `podman stop` 再 `start`，podman 會在舊路徑建一個空目錄掛上去，
資料庫看起來就像整個消失了。改名後請 `podman rm` 再 `podman-compose up -d`。
