#!/bin/bash

##############################################################################
# Supabase Edge Function 部署腳本
#
# 此腳本用於部署 save-location Edge Function 到 Supabase
#
# 使用方式：
#   ./deploy.sh [environment]
#
# 參數：
#   environment - 部署環境：local | staging | production（預設：local）
#
# 範例：
#   ./deploy.sh local      # 部署到本地開發環境
#   ./deploy.sh staging    # 部署到 staging 環境
#   ./deploy.sh production # 部署到 production 環境
##############################################################################

set -e  # 遇到錯誤立即停止

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 取得部署環境參數
ENVIRONMENT=${1:-local}

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   Supabase Edge Function 部署工具   ${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo -e "${YELLOW}部署環境：${NC}${ENVIRONMENT}"
echo ""

# 檢查 Supabase CLI 是否已安裝
if ! command -v supabase &> /dev/null; then
    echo -e "${RED}錯誤：未找到 Supabase CLI${NC}"
    echo "請先安裝 Supabase CLI："
    echo "  npm install -g supabase"
    exit 1
fi

echo -e "${GREEN}✓${NC} Supabase CLI 已安裝"

# 檢查是否在正確的目錄
if [ ! -d "supabase/functions/save-location" ]; then
    echo -e "${RED}錯誤：找不到 Edge Function 目錄${NC}"
    echo "請確認您在 Map_Function/backend 目錄下執行此腳本"
    exit 1
fi

echo -e "${GREEN}✓${NC} Edge Function 目錄存在"
echo ""

# 根據環境執行不同的部署命令
case $ENVIRONMENT in
    local)
        echo -e "${YELLOW}開始本地部署...${NC}"
        echo ""

        # 檢查本地 Supabase 是否已啟動
        if ! supabase status &> /dev/null; then
            echo -e "${YELLOW}本地 Supabase 尚未啟動，正在啟動...${NC}"
            cd ../..
            npx supabase start
            cd Map_Function/backend
        fi

        echo -e "${GREEN}✓${NC} 本地 Supabase 已運行"
        echo ""
        echo -e "${YELLOW}部署 save-location function...${NC}"

        # 本地部署只需要重啟 functions
        cd ../..
        npx supabase functions serve save-location &
        cd Map_Function/backend

        echo ""
        echo -e "${GREEN}✓${NC} Edge Function 部署成功！"
        echo ""
        echo -e "${BLUE}本地測試端點：${NC}"
        echo "  http://localhost:54321/functions/v1/save-location"
        echo ""
        echo -e "${BLUE}測試命令：${NC}"
        echo "  curl -i --location --request POST 'http://localhost:54321/functions/v1/save-location' \\"
        echo "    --header 'Authorization: Bearer YOUR_JWT_TOKEN' \\"
        echo "    --header 'Content-Type: application/json' \\"
        echo "    --data '{\"latitude\": 25.0330, \"longitude\": 121.5654, \"type\": \"家\", \"is_primary\": true}'"
        ;;

    staging)
        echo -e "${YELLOW}開始部署到 Staging 環境...${NC}"
        echo ""

        # 讀取 staging 配置
        if [ ! -f "../../.env.staging.example" ]; then
            echo -e "${RED}錯誤：找不到 .env.staging.example 配置文件${NC}"
            exit 1
        fi

        echo -e "${YELLOW}請確認您已在 Supabase Dashboard 中設定好 staging 專案${NC}"
        read -p "按 Enter 繼續，或 Ctrl+C 取消..."

        cd ../..
        npx supabase functions deploy save-location --project-ref YOUR_STAGING_PROJECT_REF
        cd Map_Function/backend

        echo ""
        echo -e "${GREEN}✓${NC} Edge Function 已部署到 Staging！"
        echo ""
        echo -e "${BLUE}Staging 測試端點：${NC}"
        echo "  https://YOUR_STAGING_PROJECT_REF.supabase.co/functions/v1/save-location"
        ;;

    production)
        echo -e "${YELLOW}開始部署到 Production 環境...${NC}"
        echo ""

        # 警告訊息
        echo -e "${RED}⚠️  警告：您即將部署到 PRODUCTION 環境！${NC}"
        echo ""
        read -p "確定要繼續嗎？(yes/no): " confirm

        if [ "$confirm" != "yes" ]; then
            echo -e "${YELLOW}部署已取消${NC}"
            exit 0
        fi

        # 讀取 production 配置
        if [ ! -f "../../.env.production.example" ]; then
            echo -e "${RED}錯誤：找不到 .env.production.example 配置文件${NC}"
            exit 1
        fi

        cd ../..
        npx supabase functions deploy save-location --project-ref YOUR_PRODUCTION_PROJECT_REF
        cd Map_Function/backend

        echo ""
        echo -e "${GREEN}✓${NC} Edge Function 已部署到 Production！"
        echo ""
        echo -e "${BLUE}Production 端點：${NC}"
        echo "  https://YOUR_PRODUCTION_PROJECT_REF.supabase.co/functions/v1/save-location"
        ;;

    *)
        echo -e "${RED}錯誤：未知的部署環境：${ENVIRONMENT}${NC}"
        echo "支援的環境：local | staging | production"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}          部署完成！                  ${NC}"
echo -e "${GREEN}======================================${NC}"
