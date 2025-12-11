#!/bin/bash

# =====================================================
# FCU Sigma 本地 CI 驗證腳本
# =====================================================
# 檔案：scripts/run-local-ci.sh
# 目標：在本地執行完整的 CI/CD 流程
# 用途：在推送前驗證所有測試是否通過

set -e  # 任何命令失敗都中止

# 配置
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$PROJECT_DIR/backend"
TESTS_DIR="$BACKEND_DIR/supabase/tests"
FUNCTIONS_DIR="$BACKEND_DIR/supabase/functions"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 計數器
TESTS_PASSED=0
TESTS_FAILED=0

# =====================================================
# 輔助函數
# =====================================================

log_section() {
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}"
}

log_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
  echo -e "${RED}❌ $1${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

# =====================================================
# 環境檢查
# =====================================================

log_section "環境檢查"

# 檢查 Docker
if ! command -v docker &> /dev/null; then
  log_error "Docker 未安裝"
  exit 1
fi
log_success "Docker 已安裝: $(docker --version)"

# 檢查 Supabase CLI
if ! command -v supabase &> /dev/null; then
  log_error "Supabase CLI 未安裝"
  exit 1
fi
log_success "Supabase CLI 已安裝: $(supabase --version)"

# 檢查 Node.js
if ! command -v node &> /dev/null; then
  log_error "Node.js 未安裝"
  exit 1
fi
log_success "Node.js 已安裝: $(node --version)"

# 檢查 Deno
if ! command -v deno &> /dev/null; then
  log_error "Deno 未安裝，請執行: brew install deno"
  exit 1
fi
log_success "Deno 已安裝: $(deno --version)"

# =====================================================
# 啟動 Supabase
# =====================================================

log_section "啟動本地 Supabase"

cd "$BACKEND_DIR"

# 檢查 Supabase 是否已在運行
if supabase status > /dev/null 2>&1; then
  log_warning "Supabase 已在運行，跳過啟動"
else
  log_warning "啟動 Supabase..."
  supabase start --workdir . --no-seed > /tmp/supabase-start.log 2>&1 || {
    log_error "Supabase 啟動失敗"
    cat /tmp/supabase-start.log
    exit 1
  }
  sleep 10
fi

log_success "Supabase 已就緒"

# =====================================================
# 執行 pgTAP SQL 測試
# =====================================================

log_section "執行 pgTAP SQL 測試"

echo "測試檔案："
ls -la "$TESTS_DIR"/*.sql 2>/dev/null | awk '{print "  - " $NF}'

# 執行所有 SQL 測試
if npx supabase test db 2>&1 | tee /tmp/sql-tests.log; then
  SQL_PASSED=$(grep -o 'ok [0-9]*' /tmp/sql-tests.log | tail -1 | awk '{print $2}' || echo "0")
  SQL_FAILED=0
  log_success "SQL 測試通過: $SQL_PASSED 個案例"
  TESTS_PASSED=$((TESTS_PASSED + SQL_PASSED))
else
  log_error "SQL 測試失敗"
  SQL_FAILED=$(grep -o 'not ok' /tmp/sql-tests.log | wc -l)
  TESTS_FAILED=$((TESTS_FAILED + SQL_FAILED))
fi

# =====================================================
# 執行 Deno 測試 (Edge Functions)
# =====================================================

log_section "執行 Deno 測試 (Edge Functions)"

if [ -f "$FUNCTIONS_DIR/analyze-item-image/analyze-item-image.test.ts" ]; then
  cd "$FUNCTIONS_DIR/analyze-item-image"

  if deno test --allow-all analyze-item-image.test.ts 2>&1 | tee /tmp/deno-tests.log; then
    DENO_PASSED=$(grep -c "^test result: ok" /tmp/deno-tests.log || echo "0")
    log_success "Deno 測試通過: $DENO_PASSED 個案例"
    TESTS_PASSED=$((TESTS_PASSED + DENO_PASSED))
  else
    log_error "Deno 測試失敗"
    DENO_FAILED=$(grep -c "^test result: FAILED" /tmp/deno-tests.log || echo "1")
    TESTS_FAILED=$((TESTS_FAILED + DENO_FAILED))
  fi
else
  log_warning "未找到 Edge Functions 測試"
fi

# =====================================================
# 執行 TypeScript API 測試
# =====================================================

log_section "執行 TypeScript API 測試"

cd "$PROJECT_DIR/backend/tests"

if deno test --allow-all transactions.api.test.ts 2>&1 | tee /tmp/ts-tests.log; then
  TS_PASSED=$(grep -c "^test result: ok" /tmp/ts-tests.log || echo "0")
  log_success "TypeScript 測試通過: $TS_PASSED 個案例"
  TESTS_PASSED=$((TESTS_PASSED + TS_PASSED))
else
  log_error "TypeScript 測試失敗"
  TS_FAILED=$(grep -c "^test result: FAILED" /tmp/ts-tests.log || echo "1")
  TESTS_FAILED=$((TESTS_FAILED + TS_FAILED))
fi

# =====================================================
# 清理 & 生成報告
# =====================================================

log_section "測試完成"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

if [ $TOTAL_TESTS -gt 0 ]; then
  PASS_RATE=$((TESTS_PASSED * 100 / TOTAL_TESTS))
else
  PASS_RATE=0
fi

echo ""
echo "=========================================="
echo "📊 測試摘要報告"
echo "=========================================="
echo -e "總測試數: ${BLUE}$TOTAL_TESTS${NC}"
echo -e "通過: ${GREEN}$TESTS_PASSED${NC}"
echo -e "失敗: ${RED}$TESTS_FAILED${NC}"
echo -e "通過率: ${BLUE}$PASS_RATE%${NC}"
echo "=========================================="
echo ""

# 根據結果設定退出碼
if [ $TESTS_FAILED -eq 0 ]; then
  log_success "所有測試通過！"

  # 打開 Supabase Dashboard (可選)
  # log_warning "在本地瀏覽器開啟 Supabase Dashboard..."
  # open http://localhost:54323 2>/dev/null || true

  exit 0
else
  log_error "部分測試失敗，請檢查日誌"
  exit 1
fi

