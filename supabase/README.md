# Supabase Migrations 目錄

本目錄包含所有 Supabase 資料庫 migration 檔案，用於管理資料庫結構變更和版本控制。

## 📁 目錄結構

```
migrations/
├── README.md                                          # 本檔案
├── CLEANUP_GUIDE.md                                   # 清理操作指南 (位於 contracts/conversationAPI/)
├── 20251025092807_create_initial_schema.sql          # 初始資料庫結構
├── 20251025093808_insert_initial_data.sql            # 初始資料
├── 20251025101010_setup_row_level_security.sql       # RLS 設定
├── ...
└── 20251116152605_transaction_before_meet_05_jin.sql # 交易流程最終版
```

## 🚀 快速開始

### 應用所有 Migrations

```bash
# 使用 Supabase CLI
supabase db push

# 或者重置並應用所有 migrations
supabase db reset
```

### 查看 Migration 狀態

```bash
# 檢查哪些 migrations 已經應用
supabase migration list

# 查看遠端資料庫狀態
supabase db remote commit
```

### 建立新 Migration

```bash
# 自動生成 migration 名稱（帶時間戳）
supabase migration new <migration_name>

# 例如：
supabase migration new add_user_preferences
```

## 📚 重要文件說明

### 核心文件

| 檔案 | 說明 | 重要性 |
|------|------|--------|
| `CLEANUP_GUIDE.md` | 清理棄用函數操作指南 (位於 contracts/conversationAPI/) | ⭐⭐⭐ |
| `20251108133713_cleanup_deprecated_functions_jo.sql` | 清理棄用函數 migration | ⭐⭐⭐ |

### Migration 時間軸

#### 初始設定 (2025-10-25 ~ 2025-10-26)
- ✅ `20251025092807_create_initial_schema.sql` - 建立初始資料庫結構
- ✅ `20251025093808_insert_initial_data.sql` - 插入初始資料
- ✅ `20251025101010_setup_row_level_security.sql` - 設定 RLS
- ✅ `20251025180327_setup_storage_rls.sql` - 設定 Storage RLS
- ✅ `20251026142101_setup_public_table_permissions.sql` - 設定權限
- ✅ `20251026144304_add_columns_main_categories.sql` - 新增欄位

#### 搜尋功能 (2025-10-28 ~ 2025-10-30)
- ✅ `20251028105137_get_searchItems_RPC.sql` - 搜尋功能 v1
- ✅ `20251029095406_get_searchItems_RPC_v2.sql` - 搜尋功能 v2
- ✅ `20251029102530_get_searchItems_RPC_v3.sql` - 搜尋功能 v3
- ✅ `20251030061942_get_searchItems_RPC_v4.sql` - 搜尋功能 v4
- ✅ `20251030063927_get_searchItems_RPC_v5.sql` - 搜尋功能 v5

#### 訊息功能 (2025-10-29)
- ✅ `20251029091800_setup_messaging_feature.sql` - 初始訊息功能

#### 其他功能 (2025-10-30 ~ 2025-11-07)
- ✅ `20251030115919_get_myFavorite_RPC.sql` - 我的最愛
- ✅ `20251030121221_get_myItems_RPC.sql` - 我的物品
- ✅ `20251031111900_get_user_primary_location_RPC.sql` - 使用者位置
- ✅ `20251101000000_get_ItemDetails_RPC_optimized.sql` - 物品詳情
- ✅ `20251102003718_create_item_function_Chris.sql` - 建立物品
- ✅ `20251103142657_create_favorite_RPC_jin.sql` - 最愛功能
- ✅ `20251103153030_get_searchItems_RPC_addColumn_favorited_at_jin.sql` - 搜尋加入最愛時間
- ✅ `20251104094940_create_auth_user_trigger_jo.sql` - Auth 觸發器
- ✅ `20251105143622_get_userProfile_RPC_jin.sql` - 使用者資料
- ✅ `20251106023822_update_locations_constraints_jo.sql` - 位置約束
- ✅ `20251106070721_get_userProfile_RPC_addColumn_created_at_jin.sql` - 使用者資料加欄位
- ✅ `20251106074315_create_follow_RPC_jin.sql` - 追蹤功能
- ✅ `20251106180000_get_my_followers_RPC_Chris.sql` - 我的粉絲
- ✅ `20251106180100_get_my_following_RPC_Chris.sql` - 我的追蹤
- ✅ `20251106190000_get_my_reviews_RPC_Chris.sql` - 我的評價
- ✅ `20251106200000_create_review_RPC_Chris.sql` - 建立評價
- ✅ `20251107000001_update_items_location_relationship_jo.sql` - 更新物品位置關聯
- ✅ `20251107000002_update_rpc_functions_use_user_location_jo.sql` - 更新 RPC 使用位置
- ✅ `20251107000003_update_create_item_function_jo.sql` - 更新建立物品函數
- ✅ `20251107000004_remove_location_id_column_jo.sql` - 移除 location_id 欄位
- ✅ `20251107100000_fix_locations_permissions_for_edge_function_jo.sql` - 修復位置權限

#### 訊息功能改進 (2025-11-08)
- ✅ `20251108050033_idx_conversations_item_buyer_unique_jo.sql` - 防止重複對話
- ✅ `20251108052733_feature_conversation_soft_delete_jo.sql` - 軟刪除功能
- ✅ `20251108120000_fix_ambiguous_column_create_or_get_conversation_jo.sql` - 修復欄位歧義
- ✅ `20251108130000_fix_all_ambiguous_columns_messaging_jo.sql` - 修復所有欄位歧義

#### 清理與優化 (2025-11-08 ~ 2025-11-09)
- ✅ `20251108133713_cleanup_deprecated_functions_jo.sql` - 清理棄用函數

#### 位置功能優化 (2025-11-09)
- ✅ `20251109000001_add_use_primary_location_to_items_jo.sql` - 新增物品使用主要位置欄位
- ✅ `20251109000002_update_create_item_with_use_primary_location_jo.sql` - 更新建立物品使用主要位置
- ✅ `20251109000003_update_search_and_details_rpc_with_use_primary_location_jo.sql` - 更新搜尋和詳情 RPC 使用主要位置

#### 使用者功能增強 (2025-11-09 ~ 2025-11-10)
- ✅ `20251109162021_get_userProfile_RPC_add_column_followed_at_jin.sql` - 使用者資料加入追蹤時間
- ✅ `20251110072258_get_userProfile_RPC_add_column_followed_at_02_jin.sql` - 使用者資料加入追蹤時間 v2

#### 儲存空間設定 (2025-11-10)
- ✅ `20251110000001_setup_storage_buckets_with_cache_jo.sql` - 設定儲存桶與快取

#### 搜尋功能擴展 (2025-11-11 ~ 2025-11-14)
- ✅ `20251111133657_get_searchItems_RPC_everyone_jin.sql` - 所有人搜尋物品
- ✅ `20251114072155_get_searchItems_RPC_everyone_approximate_location_jin.sql` - 所有人搜尋近似位置
- ✅ `20251114074824_get_searchItems_RPC_everyone_approximate_location_02_jin.sql` - 所有人搜尋近似位置 v2

#### 交易功能 (2025-11-14 ~ 2025-11-16)
- ✅ `20251114051707_add_column_to_transctions_jin.sql` - 新增交易欄位
- ✅ `20251114062232_transaction_before_meet_jin.sql` - 見面前交易功能
- ✅ `20251114064203_transaction_meet_jin.sql` - 見面交易功能
- ✅ `20251114081553_alter_transaction_status_check_jin.sql` - 修改交易狀態檢查
- ✅ `20251114085017_transaction_before_meet_02_jin.sql` - 見面前交易功能 v2
- ✅ `20251114090551_transaction_before_meet_03_jin.sql` - 見面前交易功能 v3
- ✅ `20251114101138_transaction__meet_02_jin.sql` - 見面交易功能 v2
- ✅ `20251114125127_transaction__meet_03_jin.sql` - 見面交易功能 v3
- ✅ `20251114143758_transaction_before_meet_04_jin.sql` - 見面前交易功能 v4
- ✅ `20251115081911_transactions_realTime_jin.sql` - 交易即時功能
- ✅ `20251116152605_transaction_before_meet_05_jin.sql` - 見面前交易功能最終版

#### 物品狀態管理 (2025-11-14)
- ✅ `20251114133511_update_toggleItemStatus_jin.sql` - 更新切換物品狀態
- ✅ `20251114135514_everyone_get_200000_jin.sql` - 所有人取得 200000 限制
- ✅ `20251114150137_check_users_match_profiles_and_get_200000_jin.sql` - 檢查使用者匹配並取得 200000

### 已棄用的函數 ❌

| 舊函數簽名 | 被取代於 | 狀態 |
|-----------|---------|------|
| `get_user_conversations(INT, INT)` | `get_user_conversations(INT, INT, TEXT, BOOLEAN)` | 🗑️ 已刪除 |
| `get_conversation_messages(BIGINT, INT, INT)` | `get_conversation_messages(BIGINT, INT, INT, BOOLEAN)` | 🗑️ 已刪除 |

**詳細資訊請參考:** `CLEANUP_GUIDE.md` (位於 contracts/conversationAPI/)

---

### 專案文件
- **清理操作指南:** `CLEANUP_GUIDE.md` (位於 contracts/conversationAPI/)

### 團隊聯絡
- **Backend Team** - 資料庫相關問題
- **Frontend Team** - 前端整合問題
- **DevOps Team** - 部署與基礎設施問題

## 💡 最佳實踐

1. ✅ **總是備份** - 執行重要 migration 前先備份資料庫
2. ✅ **測試優先** - 在測試環境驗證後再部署到生產環境
3. ✅ **使用描述性名稱** - Migration 檔案名稱要清楚說明變更內容
4. ✅ **保持冪等性** - Migration 應該可以安全地重複執行
5. ✅ **記錄變更** - 在 migration 中加入註解說明原因和影響
6. ✅ **版本控制** - 所有 migration 都應該納入 Git 版本控制

## 🔒 安全注意事項

- 🔐 使用 `SECURITY DEFINER` 時要特別小心，確保不會暴露敏感資料
- 🔐 RLS (Row Level Security) 要始終啟用並正確設定
- 🔐 函數的權限要明確授予，避免使用 `GRANT ALL`
- 🔐 敏感資料（如密碼、API Key）永遠不要寫在 migration 中

---

**維護者:** Backend Team  
**最後更新:** 2025-11-17  
**版本:** 1.1
