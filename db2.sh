#!/bin/bash

# =========================
# DB2 設定
# =========================
DB_NAME="PTPMSDB"
DB_USER="ptpmsap"
DB_PASS="A@t123456"

LOG_FILE="db2_optimization_$(date +%Y%m%d_%H%M%S).log"

echo "=== Start DB2 Optimization ===" | tee -a $LOG_FILE

# =========================
# 連線
# =========================
db2 connect to $DB_NAME user $DB_USER using $DB_PASS >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    echo "DB Connect Failed" | tee -a $LOG_FILE
    exit 1
fi

# =========================
# 預檢：重複資料
# =========================
echo "=== Checking duplicates ===" | tee -a $LOG_FILE

CHECK_DEP=$(db2 -x "SELECT COUNT(*) FROM (SELECT cityCode, vochNo FROM ptpmsap.PBM_DEPVOCH GROUP BY cityCode, vochNo HAVING COUNT(*) > 1) AS t")
CHECK_EXP=$(db2 -x "SELECT COUNT(*) FROM (SELECT cityCode, vochNo FROM ptpmsap.PBM_EXPVOCH GROUP BY cityCode, vochNo HAVING COUNT(*) > 1) AS t")

echo "PBM_DEPVOCH duplicates: $CHECK_DEP" | tee -a $LOG_FILE
echo "PBM_EXPVOCH duplicates: $CHECK_EXP" | tee -a $LOG_FILE

if [ "$CHECK_DEP" -ne 0 ] || [ "$CHECK_EXP" -ne 0 ]; then
    echo "Duplicate data found, aborting index creation!" | tee -a $LOG_FILE
    db2 connect reset
    exit 1
fi

# =========================
# 建立索引
# =========================
echo "=== Creating indexes ===" | tee -a $LOG_FILE

db2 "CREATE UNIQUE INDEX UK_PBM_DEPVOCH_CITYCODE_VOCHNO ON ptpmsap.Pbm_DepVoch (cityCode, vochNo)" >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    echo "Create index on PBM_DEPVOCH failed" | tee -a $LOG_FILE
    exit 1
fi

db2 "CREATE UNIQUE INDEX UK_cityCode_vochNo ON ptpmsap.Pbm_ExpVoch (cityCode, vochNo)" >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    echo "Create index on PBM_EXPVOCH failed" | tee -a $LOG_FILE
    exit 1
fi

# =========================
# REORG + RUNSTATS
# =========================
echo "=== REORG & RUNSTATS ===" | tee -a $LOG_FILE

db2 "CALL SYSPROC.ADMIN_CMD('REORG TABLE ptpmsap.PBM_DEPVOCH ALLOW WRITE ACCESS')" >> $LOG_FILE 2>&1
db2 "CALL SYSPROC.ADMIN_CMD('REORG INDEXES ALL FOR TABLE ptpmsap.PBM_DEPVOCH ALLOW WRITE ACCESS')" >> $LOG_FILE 2>&1
db2 "CALL SYSPROC.ADMIN_CMD('RUNSTATS ON TABLE ptpmsap.PBM_DEPVOCH WITH DISTRIBUTION AND DETAILED INDEXES ALL')" >> $LOG_FILE 2>&1

db2 "CALL SYSPROC.ADMIN_CMD('REORG TABLE ptpmsap.PBM_EXPVOCH ALLOW WRITE ACCESS')" >> $LOG_FILE 2>&1
db2 "CALL SYSPROC.ADMIN_CMD('REORG INDEXES ALL FOR TABLE ptpmsap.PBM_EXPVOCH ALLOW WRITE ACCESS')" >> $LOG_FILE 2>&1
db2 "CALL SYSPROC.ADMIN_CMD('RUNSTATS ON TABLE ptpmsap.PBM_EXPVOCH WITH DISTRIBUTION AND DETAILED INDEXES ALL')" >> $LOG_FILE 2>&1

# =========================
# 完成
# =========================
db2 connect reset >> $LOG_FILE 2>&1

echo "DB2 Optimization Completed" | tee -a $LOG_FILE