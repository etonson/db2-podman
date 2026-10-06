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
| `backups/{database}/` | 資料庫備份檔與 `metadata.json`，bind mount 成容器的 `/database/backups` | 只有 `metadata.json` |
| `custom/` | 開機時自動執行的初始化腳本（還原資料庫、建帳號），會複製到 `/var/custom/` | 是 |

資料庫本體（實例、資料、日誌）放在具名 volume `db2_data` 裡，由 podman 管理，
不落在專案目錄下。這樣可以避開 rootless podman 的 uid 映射問題，
專案目錄改名或執行 `git clean` 也不會弄丟資料庫。要清掉整個資料庫重來：

```bash
podman-compose down
podman volume rm db2-podman_db2_data
```

## 常用指令

### 進入容器
```bash
podman exec -it db2-gtky su - db2inst1
db2 connect to PTPMSDB user ptpmsap using 'A@t123456'
```

### DB2 基本操作

以下都在 `su - db2inst1` 之後、`db2 connect` 連上資料庫的狀態下執行。
SQL 要用雙引號包起來，否則 `*`、`(` 之類的字元會先被 shell 解讀。

不想進容器互動時，可以在宿主機一行執行完：

```bash
podman exec db2-gtky su - db2inst1 -c \
  "db2 connect to PTPMSDB user ptpmsap using 'A@t123456' >/dev/null && db2 list tables for schema PTPMSAP"
```

#### 查看 schema

```bash
db2 values current schema                  # 目前預設 schema（預設等於登入帳號）
db2 set schema PTPMSAP                     # 切換預設 schema，之後 SQL 可省略 PTPMSAP. 前綴

# 列出使用者自建的 schema（排除 SYS* 系統 schema）
db2 "SELECT SCHEMANAME, OWNER FROM SYSCAT.SCHEMATA
     WHERE SCHEMANAME NOT LIKE 'SYS%' AND SCHEMANAME NOT IN ('NULLID', 'SQLJ')"
```

本機正常會看到 `PTPMSAP`（應用程式資料表）、`DB2EPTS`、`LIQUIBASE`（migrator 的追蹤表）。

#### 列出資料表（show tables）

```bash
db2 list tables                            # 目前 schema 的資料表
db2 list tables for schema PTPMSAP         # 指定 schema
db2 list tables for all                    # 所有 schema（含系統表，很長）

# 用系統目錄查，可以自己加條件或排序
db2 "SELECT TABNAME, TYPE FROM SYSCAT.TABLES
     WHERE TABSCHEMA = 'PTPMSAP' ORDER BY TABNAME"
```

`TYPE`：`T` 資料表、`V` 檢視表、`A` 別名。

#### 查看資料表結構（describe）

```bash
db2 describe table PTPMSAP.COMMON_CODE                 # 欄位、型別、長度、可否為 NULL
db2 describe indexes for table PTPMSAP.COMMON_CODE     # 索引

# 匯出建表 DDL（db2look 是獨立指令，不需要先 connect）
db2look -d PTPMSDB -z PTPMSAP -t COMMON_CODE -e

# 找出哪些資料表有某個欄位
db2 "SELECT TABSCHEMA, TABNAME FROM SYSCAT.COLUMNS WHERE COLNAME = 'CODEKINDID'"
```

DB2 的物件名稱一律存成**大寫**，系統目錄查詢的條件也要用大寫（`'COMMON_CODE'`，不是 `'common_code'`）。

#### 查詢資料

```bash
db2 "SELECT * FROM PTPMSAP.COMMON_CODE FETCH FIRST 10 ROWS ONLY"   # DB2 沒有 LIMIT

# CLP 會依欄位定義長度輸出，VARCHAR(500) 會印得非常寬，可以用 SUBSTR 截短
db2 "SELECT CODENAME, SUBSTR(CODEDESC1, 1, 40) AS VAL FROM PTPMSAP.COMMON_CODE"
```

#### 執行 SQL 檔

```bash
db2 -tvf /tmp/script.sql          # -t 以 ; 分隔、-v 顯示每一句、-f 讀檔
db2 +c -tvf /tmp/script.sql       # +c 關閉 autocommit，確認後再 db2 commit 或 db2 rollback
```

檔案要先從宿主機複製進容器，並讓 `db2inst1` 讀得到：

```bash
podman cp ./script.sql db2-gtky:/tmp/script.sql
podman exec db2-gtky chmod 644 /tmp/script.sql
```

#### 其他常用

```bash
db2 list active databases         # 目前啟用中的資料庫與連線數
db2 list applications             # 誰連著資料庫（實例層級指令，靠 su - db2inst1 的身分執行）
db2 "SELECT ID, AUTHOR, FILENAME, DATEEXECUTED FROM LIQUIBASE.DATABASECHANGELOG"   # migrator 套用紀錄
db2 terminate                     # 結束連線與 CLP 背景程序
```

直接輸入 `db2` 會進入互動模式（提示字元 `db2 =>`），裡面的指令不用加 `db2` 前綴、
也不用引號，輸入 `quit` 離開。

### 備份與還原
詳細規範見 [BACKUP.md](BACKUP.md)。常用的是：

```bash
./backup.sh                 # 互動式選單，列出容器內所有資料庫供選擇
./backup.sh PTPMSDB         # 直接備份指定的資料庫
```

還原是**容器啟動時自動做的**：把備份放進 `backups/{database}/`，
清掉 `db2_data` volume 後重建容器，`custom/restore-databases.sh` 就會掃描並還原。
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

### 不要把 `/database` bind mount 到專案目錄
早期版本用 `./db2_storage:/database`，踩到兩個坑，改用具名 volume 後都消失了：

1. **容器啟動後立刻 exit 1**：rootless podman 的 uid 映射會讓
   `sqllib/adm/fencedid` 在容器內變成 `root:root`，`db2icrt` 拒絕建立實例：
   ```
   DBI20187E  The fencedid file ".../sqllib/adm/fencedid" is invalid because it is
   not owned by the "root":"db2iadm1".
   ```
2. **改名專案目錄後資料庫像是消失了**：bind mount 的來源路徑在建立容器時就寫死，
   目錄改名後 `podman start` 會在舊路徑建一個空目錄掛上去。

### 具名 volume 要加上 `suid,dev,exec`
podman 的具名 volume 預設帶 `nosuid,nodev`，而 DB2 開機時會把 `/database`
重新掛成 suid（`sqllib/adm/` 底下有 setuid 執行檔）。少了這個選項會看到：

```
(*) Remounting /database with suid... 
mount: /database: permission denied.
SQL1042C  An unexpected system error occurred.
```

### 資料庫名稱上限 8 個字元
`backups/` 的目錄名就是目標資料庫名稱，超過 8 個字元會被 `SQL2040N` 擋下來。
