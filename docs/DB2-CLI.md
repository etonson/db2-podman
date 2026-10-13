# DB2 CLI 操作

## 連線

先進入容器並切換至實例管理者：

```bash
podman exec -it db2-gtky su - db2inst1
db2 connect to PTPMSDB user ptpmsap using 'A@t123456'
```

之後的 `db2` 指令均在容器內執行。若只需從宿主機快速查詢，可用：

```bash
podman exec db2-gtky su - db2inst1 -c \
  "db2 connect to PTPMSDB user ptpmsap using 'A@t123456' >/dev/null && db2 list tables for schema PTPMSAP"
```

## Schema 與資料表

`CURRENT SCHEMA` 是未限定物件名稱時使用的預設 Schema；`CURRENT USER` 是目前授權使用者。`LIST TABLES` 有自己的預設列示範圍，要指定範圍請使用 `FOR SCHEMA`。

```bash
db2 values current schema
db2 values current user
db2 set schema PTPMSAP
db2 list tables for schema PTPMSAP
db2 list tables for all
```

列出使用者建立的 Schema：

```bash
db2 "SELECT SCHEMANAME, OWNER FROM SYSCAT.SCHEMATA
     WHERE SCHEMANAME NOT LIKE 'SYS%'
       AND SCHEMANAME NOT IN ('NULLID', 'SQLJ')"
```

本機預期可看到應用程式的 `PTPMSAP`、遷移紀錄的 `LIQUIBASE`，以及 DB2 相關的 `DB2EPTS`。列出 `PTPMSAP` 物件及類型：

```bash
db2 "SELECT TABNAME, TYPE FROM SYSCAT.TABLES
     WHERE TABSCHEMA = 'PTPMSAP' ORDER BY TABNAME"
```

`TYPE` 的 `T`、`V`、`A` 分別是資料表、檢視表、別名。

```bash
db2 describe table PTPMSAP.COMMON_CODE
db2 describe indexes for table PTPMSAP.COMMON_CODE
db2look -d PTPMSDB -z PTPMSAP -t COMMON_CODE -e
db2 "SELECT TABSCHEMA, TABNAME FROM SYSCAT.COLUMNS WHERE COLNAME = 'CODEKINDID'"
```

`db2look` 是獨立工具，不必先 `db2 connect`。未使用雙引號界定的 DB2 識別字會轉成大寫，查系統目錄時也應使用 `'COMMON_CODE'`；以雙引號建立的大小寫敏感名稱除外。

## SQL 查詢與檔案

一般指令模式下，每句前面加 `db2`，SQL 用引號包住，避免 Shell 解析 `*` 等字元。DB2 使用 `FETCH FIRST ... ROWS ONLY` 限制筆數：

```bash
db2 "SELECT * FROM PTPMSAP.COMMON_CODE FETCH FIRST 10 ROWS ONLY"
db2 "SELECT CODENAME, SUBSTR(CODEDESC1, 1, 40) AS VAL FROM PTPMSAP.COMMON_CODE"
```

`SUBSTR` 可避免 CLP 依 `VARCHAR` 定義長度印出過寬結果。執行宿主機上的 SQL 檔：

```bash
podman cp ./script.sql db2-gtky:/tmp/script.sql
podman exec db2-gtky chmod 644 /tmp/script.sql
```

接著在已連線的容器 Shell 中執行：

```bash
db2 -tvf /tmp/script.sql
```

`-t` 以分號結束 SQL，`-v` 顯示執行內容，`-f` 從檔案讀取。`+c` 可關閉自動提交：

```bash
db2 +c -tvf /tmp/script.sql
```

需要明確控制交易時，將 `COMMIT` 或 `ROLLBACK` 寫入同一份腳本，或在同一個 CLP 互動工作階段操作，並先測試失敗時的處理。不要假設另一次 `db2` 呼叫必定接續未提交交易；部分 DDL 也可能涉及隱含提交。

## 互動模式

輸入 `db2` 會進入 `db2 =>` 提示字元。指令不加 `db2` 前綴，SQL 不需 Shell 引號，預設也不加分號：

```text
$ db2
db2 => connect to PTPMSDB user ptpmsap using A@t123456
db2 => set schema PTPMSAP
db2 => list tables for schema PTPMSAP
db2 => describe table PTPMSAP.COMMON_CODE
db2 => SELECT * FROM PTPMSAP.COMMON_CODE FETCH FIRST 10 ROWS ONLY
db2 => quit
```

預設模式輸入 `connect to PTPMSDB;` 可能得到 `SQL1001N "PTPMSDB;" is not a valid database name`；未連線時執行 SQL 則會得到 `SQL1024N`。需要多行 SQL 與分號時，改用 `db2 -t`：

```text
$ db2 -t
db2 => connect to PTPMSDB user ptpmsap using A@t123456;
db2 => SELECT CODENAME, CODEDESC1
db2 (cont.) => FROM PTPMSAP.COMMON_CODE FETCH FIRST 10 ROWS ONLY;
db2 => quit;
```

`quit` 離開互動模式；要清理 CLP 背景程序與連線，執行 `db2 terminate`。

## 維運查詢

```bash
db2 list active databases
db2 list applications
db2 "SELECT ID, AUTHOR, FILENAME, DATEEXECUTED FROM LIQUIBASE.DATABASECHANGELOG"
db2 terminate
```

`LIST APPLICATIONS` 是實例層級指令，請以 `db2inst1` 身分執行。
