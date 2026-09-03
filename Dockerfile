FROM icr.io/db2_community/db2:latest

# 將初始化腳本放進 /var/custom/，官方 entrypoint 會依檔名順序自動執行
# 這些腳本會以 root 身份執行
#   restore-databases.sh 先跑（從 backups/ 還原資料庫）
#   setup-app-user.sh    後跑（建立應用程式帳號並授權）
COPY custom/ /var/custom/
RUN chmod +x /var/custom/*.sh
