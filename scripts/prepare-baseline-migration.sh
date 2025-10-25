#!/bin/bash
# scripts/prepare-baseline-migration.sh

set -e

echo "📝 準備 Baseline Migration..."

# 1. 確保本地環境乾淨
npx supabase db reset

# 2. 備份現有 migrations (以防萬一)
cp -r supabase/migrations supabase/migrations.backup

# 3. 壓縮所有 migrations
echo "🗜️ 壓縮 migrations..."
npx supabase migration squash

# 4. 找到壓縮後的檔案 (最新的 migration 檔案)
LATEST_MIGRATION=$(ls -t supabase/migrations/*.sql | head -1)
BASELINE_NAME="supabase/migrations/$(date +%Y%m%d%H%M%S)_baseline_v2.sql"

# 5. 重新命名為 baseline
mv "$LATEST_MIGRATION" "$BASELINE_NAME"

echo "✅ Baseline migration 已建立: $BASELINE_NAME"

# 6. 在檔案開頭加入說明
cat > /tmp/baseline_header.sql << 'EOF'
-- ============================================================================
-- BASELINE MIGRATION: Version 2.0
-- ============================================================================
-- 此 migration 代表系統完整的 baseline schema
-- 執行此 migration 後,Staging 資料庫將與本地開發環境完全一致
--
-- 建立時間: $(date +%Y-%m-%d\ %H:%M:%S)
-- 建立者: $(git config user.name)
-- Git Commit: $(git rev-parse --short HEAD)
--
-- ⚠️  警告: 此 migration 會清空並重建所有 schema
-- 適用情境: Staging 環境全新重置
-- ============================================================================

EOF

cat /tmp/baseline_header.sql "$BASELINE_NAME" > /tmp/baseline_with_header.sql
mv /tmp/baseline_with_header.sql "$BASELINE_NAME"

echo "✅ 已加入 baseline 說明"
