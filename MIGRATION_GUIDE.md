# Migration 管理指南

本文檔說明如何管理、比對和推送 Supabase Migrations。

---

## 📋 目錄

- [快速參考](#快速參考)
- [比對本地與遠端 Migrations](#比對本地與遠端-migrations)
- [推送 Migrations 到遠端](#推送-migrations-到遠端)
- [完整部署流程](#完整部署流程)
- [常見問題排除](#常見問題排除)

---

## 快速參考

### 常用指令速查表

| 操作 | 指令 |
|------|------|
| 查看本地 migrations | `supabase migration list --local` |
| 查看遠端 migrations | `supabase migration list --linked` |
| 比對差異 | `supabase db diff --linked --schema public` |
| 推送 migrations | `supabase db push --linked` |
| 連接到遠端專案 | `supabase link --project-ref YOUR_PROJECT_REF` |
| 部署 Edge Function | `supabase functions deploy FUNCTION_NAME` |

---

## 比對本地與遠端 Migrations

### 方法 1：使用 Supabase CLI（推薦）

#### 1.1 連接到遠端環境

```bash
# 連接到 staging 環境
supabase link --project-ref your-staging-project-ref

# 如果使用 .env.staging
export $(cat .env.staging | xargs)
supabase link --project-ref $SUPABASE_PROJECT_REF
```

#### 1.2 列出並比對 Migrations

```bash
# 查看本地 migrations
supabase migration list --local

# 查看遠端 migrations
supabase migration list --linked

# 比對本地與遠端的 schema 差異
supabase db diff --linked --schema public

# 產生差異 SQL 檔案
supabase db diff --linked --schema public --file diff_report.sql
```

**輸出範例**：
```
Local migrations:
  20251025092807_create_initial_schema.sql
  20251025093808_insert_initial_data.sql
  20251031111900_get_user_primary_location_RPC.sql ← 新增的

Remote migrations:
  20251025092807_create_initial_schema.sql
  20251025093808_insert_initial_data.sql
```

### 方法 2：查看檔案清單

```bash
# 列出本地所有 migrations（依時間排序）
ls -lt supabase/migrations/

# 查看最新的 5 個 migrations
ls -lt supabase/migrations/ | head -6

# 統計 migrations 數量
echo "本地 Migrations 數量: $(ls -1 supabase/migrations/*.sql | wc -l)"
```

### 方法 3：查詢遠端資料庫記錄

```bash
# 查詢遠端資料庫的 migration 記錄
supabase db remote exec "
  SELECT
    version,
    name,
    inserted_at
  FROM supabase_migrations.schema_migrations
  ORDER BY version DESC
  LIMIT 10;
"
```

### 方法 4：完整 Schema 比對

```bash
# 1. 導出本地 schema
supabase db dump --local --schema public > local_schema.sql

# 2. 導出遠端 schema
supabase db dump --linked --schema public > remote_schema.sql

# 3. 使用 diff 比對
diff local_schema.sql remote_schema.sql > schema_diff.txt

# 4. 查看差異
cat schema_diff.txt

# 或使用更友善的比對工具
code --diff local_schema.sql remote_schema.sql  # VSCode
```

### 方法 5：一鍵比對腳本

```bash
#!/bin/bash
# compare_migrations.sh

echo "======================================"
echo "    Migrations 比對報告"
echo "======================================"
echo ""

echo "📁 本地 Migrations:"
echo "-------------------------------------"
ls -1 supabase/migrations/ | nl
echo ""

echo "☁️  遠端 Migrations:"
echo "-------------------------------------"
supabase migration list --linked
echo ""

echo "🔍 Schema 差異:"
echo "-------------------------------------"
supabase db diff --linked --schema public
echo ""

echo "✅ 比對完成！"
```

**使用方法**：
```bash
chmod +x compare_migrations.sh
./compare_migrations.sh
```

---

## 推送 Migrations 到遠端

### 前置準備

#### 1. 確認環境連接

```bash
# 檢查當前連接狀態
supabase status

# 如果尚未連接，先連接到遠端
supabase link --project-ref YOUR_PROJECT_REF
```

#### 2. 備份遠端資料庫（強烈建議）

```bash
# 備份當前遠端資料庫
supabase db dump --linked > backup_$(date +%Y%m%d_%H%M%S).sql

# 或備份到專門的目錄
mkdir -p backups
supabase db dump --linked > backups/backup_staging_$(date +%Y%m%d_%H%M%S).sql
```

#### 3. 預覽將要推送的變更

```bash
# 查看將要推送的 migrations
supabase migration list --local

# 查看 schema 差異
supabase db diff --linked --schema public
```

### 推送流程

#### 步驟 1：推送 Migrations

```bash
# 推送所有尚未套用的 migrations
supabase db push --linked

# 如果需要指定環境
supabase db push --project-ref YOUR_PROJECT_REF
```

#### 步驟 2：驗證推送結果

```bash
# 檢查遠端 migrations 列表
supabase migration list --linked

# 驗證新增的 RPC 函數
supabase db remote exec "
  SELECT
    routine_name,
    routine_type
  FROM information_schema.routines
  WHERE routine_schema = 'public'
  ORDER BY routine_name;
"

# 測試新的 RPC 函數（以 get_user_primary_location 為例）
supabase db remote exec "
  SELECT * FROM get_user_primary_location('00000000-0000-0000-0000-000000000000');
"
```

#### 步驟 3：部署相關的 Edge Functions

```bash
# 部署單個 Edge Function
supabase functions deploy save-location

# 部署所有 Edge Functions
supabase functions deploy

# 驗證部署
supabase functions list
```

### 使用腳本推送

創建 `push_migrations.sh`：

```bash
#!/bin/bash
# push_migrations.sh - 安全推送 Migrations 到遠端

set -e  # 遇到錯誤立即停止

echo "======================================"
echo "    Migrations 推送流程"
echo "======================================"
echo ""

# 1. 檢查連接
echo "📡 檢查連接狀態..."
supabase status
echo ""

# 2. 備份
echo "💾 備份遠端資料庫..."
mkdir -p backups
BACKUP_FILE="backups/backup_$(date +%Y%m%d_%H%M%S).sql"
supabase db dump --linked > $BACKUP_FILE
echo "✅ 備份完成: $BACKUP_FILE"
echo ""

# 3. 預覽變更
echo "🔍 預覽將要推送的變更..."
supabase migration list --local
echo ""
supabase db diff --linked --schema public
echo ""

# 4. 確認推送
read -p "確定要推送嗎？(y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ 取消推送"
    exit 1
fi

# 5. 推送 migrations
echo "🚀 推送 Migrations..."
supabase db push --linked
echo ""

# 6. 驗證
echo "✅ 驗證推送結果..."
supabase migration list --linked
echo ""

# 7. 部署 Edge Functions
echo "📦 部署 Edge Functions..."
supabase functions deploy
echo ""

echo "======================================"
echo "✅ 推送完成！"
echo "======================================"
```

**使用方法**：
```bash
chmod +x push_migrations.sh
./push_migrations.sh
```

---

## 完整部署流程

### 情境：將新的 Migration 從開發環境部署到 Staging

#### 1. 提交到 Git

```bash
# 查看變更
git status

# 添加新的 migration 檔案
git add supabase/migrations/20251031111900_get_user_primary_location_RPC.sql

# 添加修改的 Edge Function
git add database/functions/Map_function/backend/supabase/functions/

# 查看將要提交的內容
git diff --cached

# 提交
git commit -m "feat: add get_user_primary_location RPC and update save-location Edge Function

- Add get_user_primary_location RPC function to extract coordinates from PostGIS
- Update save-location Edge Function to support GET/POST methods
- GET: fetch user's saved primary location
- POST: insert new location or update existing one (avoid duplicates)
- Add comprehensive API documentation"

# 推送到遠端 git 分支
git push origin dev_chris_map
```

#### 2. 推送到 Staging

```bash
# 連接到 staging（如果尚未連接）
supabase link --project-ref YOUR_STAGING_PROJECT_REF

# 備份 staging 資料庫
mkdir -p backups
supabase db dump --linked > backups/staging_backup_$(date +%Y%m%d_%H%M%S).sql

# 預覽差異
supabase db diff --linked --schema public

# 推送 migrations
supabase db push --linked

# 驗證
supabase migration list --linked
```

#### 3. 部署 Edge Functions

```bash
# 部署 save-location Edge Function
supabase functions deploy save-location --project-ref YOUR_STAGING_PROJECT_REF

# 或使用專案中的 deploy.sh
cd database/functions/Map_function/backend
./deploy.sh

# 驗證部署
supabase functions list
```

#### 4. 測試

```bash
# 測試 RPC 函數
supabase db remote exec "
  SELECT * FROM get_user_primary_location('test-user-id');
"

# 測試 Edge Function (GET)
curl -X GET 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/save-location' \
  -H 'Authorization: Bearer YOUR_JWT_TOKEN'

# 測試 Edge Function (POST)
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/save-location' \
  -H 'Authorization: Bearer YOUR_JWT_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"latitude": 25.0330, "longitude": 121.5654}'
```

### 一鍵部署腳本

創建 `deploy_to_staging.sh`：

```bash
#!/bin/bash
# deploy_to_staging.sh - 完整部署流程

set -e

BRANCH="dev_chris_map"
STAGING_REF="YOUR_STAGING_PROJECT_REF"

echo "======================================"
echo "    完整部署流程 to Staging"
echo "======================================"
echo ""

# 1. Git 操作
echo "📝 Git 提交..."
git add supabase/migrations/
git add database/functions/Map_function/backend/supabase/functions/
git status
read -p "確認提交並推送到 Git？(y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    git commit -m "feat: update migrations and edge functions"
    git push origin $BRANCH
    echo "✅ Git 推送完成"
else
    echo "⏭️  跳過 Git 操作"
fi
echo ""

# 2. 連接 Staging
echo "📡 連接到 Staging..."
supabase link --project-ref $STAGING_REF
echo ""

# 3. 備份
echo "💾 備份 Staging 資料庫..."
mkdir -p backups
BACKUP_FILE="backups/staging_$(date +%Y%m%d_%H%M%S).sql"
supabase db dump --linked > $BACKUP_FILE
echo "✅ 備份完成: $BACKUP_FILE"
echo ""

# 4. 推送 Migrations
echo "🚀 推送 Migrations..."
supabase db diff --linked --schema public
read -p "確認推送 Migrations？(y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    supabase db push --linked
    echo "✅ Migrations 推送完成"
else
    echo "❌ 取消推送"
    exit 1
fi
echo ""

# 5. 部署 Edge Functions
echo "📦 部署 Edge Functions..."
supabase functions deploy save-location --project-ref $STAGING_REF
echo "✅ Edge Functions 部署完成"
echo ""

# 6. 驗證
echo "✅ 驗證部署..."
echo "Migrations:"
supabase migration list --linked
echo ""
echo "Edge Functions:"
supabase functions list
echo ""

echo "======================================"
echo "✅ 部署完成！"
echo "======================================"
echo ""
echo "📋 後續步驟:"
echo "1. 測試 Staging 環境功能"
echo "2. 確認無誤後，建立 Pull Request 到 main 分支"
echo "3. Code Review 後合併"
echo "4. 部署到 Production"
```

**使用方法**：
```bash
chmod +x deploy_to_staging.sh
./deploy_to_staging.sh
```

---

## 常見問題排除

### Q1: 推送時出現 "migration already exists" 錯誤

**原因**：遠端已經有相同版本號的 migration

**解決方法**：
```bash
# 查看遠端已套用的 migrations
supabase migration list --linked

# 如果確認本地版本正確，可以強制重新套用
supabase db reset --linked  # ⚠️ 危險：會清空資料庫

# 或手動修改 migration 版本號（推薦）
# 重新命名檔案，使用新的時間戳
mv supabase/migrations/old_name.sql supabase/migrations/$(date +%Y%m%d%H%M%S)_new_name.sql
```

### Q2: 推送後 RPC 函數無法使用

**檢查方法**：
```bash
# 1. 確認函數存在
supabase db remote exec "
  SELECT routine_name
  FROM information_schema.routines
  WHERE routine_schema = 'public'
    AND routine_name = 'get_user_primary_location';
"

# 2. 檢查函數權限
supabase db remote exec "
  SELECT
    routine_name,
    grantee,
    privilege_type
  FROM information_schema.routine_privileges
  WHERE routine_name = 'get_user_primary_location';
"

# 3. 測試執行
supabase db remote exec "
  SELECT * FROM get_user_primary_location('00000000-0000-0000-0000-000000000000');
"
```

### Q3: Edge Function 部署後無法存取

**檢查清單**：
```bash
# 1. 確認 Edge Function 已部署
supabase functions list

# 2. 檢查函數日誌
supabase functions logs save-location

# 3. 測試函數
curl -i https://YOUR_PROJECT_REF.supabase.co/functions/v1/save-location \
  -H 'Authorization: Bearer YOUR_ANON_KEY'

# 4. 檢查環境變數
supabase secrets list
```

### Q4: 如何回滾 Migration

```bash
# ⚠️ Supabase 不支援自動回滾，需要手動處理

# 方法 1: 使用備份還原
supabase db reset --linked
psql -h YOUR_DB_HOST -U postgres -d postgres < backups/backup_file.sql

# 方法 2: 建立反向 migration
supabase migration new revert_previous_change
# 在新 migration 中編寫 DROP 或 ALTER 語句來撤銷變更

# 方法 3: 手動刪除 migration 記錄（不推薦）
supabase db remote exec "
  DELETE FROM supabase_migrations.schema_migrations
  WHERE version = '20251031111900';
"
```

### Q5: 本地和遠端 Schema 衝突

```bash
# 1. 備份本地資料
supabase db dump --local > local_backup.sql

# 2. 重置本地資料庫並從遠端同步
supabase db pull

# 3. 比對差異
supabase db diff --linked --schema public

# 4. 如果需要，建立新的 migration 來解決衝突
supabase migration new resolve_schema_conflict
```

### Q6: 推送速度很慢

```bash
# 檢查網路連接
ping db.YOUR_PROJECT_REF.supabase.co

# 使用更快的 migration 方式（如果 migrations 很多）
supabase db push --linked --include-seed=false

# 或分批推送
supabase db push --linked --include-migration="20251031111900_*"
```

---

## 最佳實踐

### 1. Migration 命名規範

```
格式: YYYYMMDDHHMMSS_descriptive_name.sql

範例:
✅ 20251031111900_get_user_primary_location_RPC.sql
✅ 20251031120000_add_email_index_to_users.sql
❌ fix.sql
❌ update.sql
```

### 2. 推送前檢查清單

- [ ] 本地 migrations 已測試
- [ ] 已備份遠端資料庫
- [ ] 已預覽 schema 差異
- [ ] 已通知團隊成員
- [ ] 選擇低峰時段推送
- [ ] 準備好回滾方案

### 3. Migration 內容建議

```sql
-- ✅ 好的 Migration
BEGIN;

-- 說明變更目的
COMMENT ON FUNCTION get_user_primary_location IS '獲取使用者主要位置';

-- 使用 IF EXISTS 避免錯誤
DROP FUNCTION IF EXISTS old_function_name;

-- 建立新功能
CREATE FUNCTION ...;

-- 設定權限
GRANT EXECUTE ON FUNCTION ... TO authenticated;

COMMIT;
```

### 4. 團隊協作

```bash
# 推送前同步團隊最新 migrations
git pull origin main
supabase db pull

# 推送後通知團隊
git push origin dev_chris_map
# 在 PR 中說明 migration 變更

# 定期清理舊的 backup 檔案
find backups/ -name "*.sql" -mtime +30 -delete
```

---

## 環境配置

### .env.staging 設定範例

```bash
# Supabase Staging 環境
SUPABASE_PROJECT_REF=your-staging-project-ref
SUPABASE_URL=https://your-staging-project-ref.supabase.co
SUPABASE_ANON_KEY=your-staging-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-staging-service-role-key
SUPABASE_DB_PASSWORD=your-staging-db-password
```

### 使用環境變數

```bash
# 載入 staging 環境變數
export $(cat .env.staging | xargs)

# 連接到 staging
supabase link --project-ref $SUPABASE_PROJECT_REF

# 推送
supabase db push --linked
```

---

## 相關文檔

- [Supabase CLI 文檔](https://supabase.com/docs/guides/cli)
- [Migration 指南](https://supabase.com/docs/guides/cli/local-development#database-migrations)
- [專案 CLAUDE.MD](./CLAUDE.MD) - 專案架構說明
- [Edge Function README](./database/functions/Map_function/backend/supabase/functions/save-location/README.md)

---

**維護者**: FCU-Sigmaboy Team
**最後更新**: 2025-10-31
**版本**: 1.0.0
