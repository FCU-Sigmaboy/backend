#!/bin/bash
# scripts/verify-baseline-migration.sh

set -e

echo "🧪 驗證 Baseline Migration..."

# 測試 5 次確保穩定
for i in {1..5}; do
  echo "🔄 第 $i 次測試..."

  # 完全重置本地資料庫
  npx supabase db reset

  # 驗證表格
  psql "postgresql://postgres:postgres@localhost:54322/postgres" << 'EOF'
  \dt public.*
  SELECT
    'Tables' AS type,
    COUNT(*) AS count
  FROM information_schema.tables
  WHERE table_schema = 'public'
  UNION ALL
  SELECT
    'Functions',
    COUNT(*)
  FROM information_schema.routines
  WHERE routine_schema = 'public'
  UNION ALL
  SELECT
    'Triggers',
    COUNT(*)
  FROM information_schema.triggers
  WHERE trigger_schema = 'public';
EOF

  # 測試應用程式
  npm run build

  echo "✅ 第 $i 次測試通過"
done

echo "✅ Baseline Migration 驗證通過!"
