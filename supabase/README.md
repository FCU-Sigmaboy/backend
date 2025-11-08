# Supabase Migrations 目錄

本目錄包含所有 Supabase 資料庫 migration 檔案，用於管理資料庫結構變更和版本控制。

## 📁 目錄結構

```
migrations/
├── README.md                                          # 本檔案
<!-- DEPRECATED_FUNCTIONS_EVALUATION.md 檔案尚未建立，請參考 CLEANUP_GUIDE.md 以取得相關資訊 -->
├── CLEANUP_GUIDE.md                                   # 清理操作指南
├── 20251025092807_create_initial_schema.sql          # 初始資料庫結構
├── 20251025093808_insert_initial_data.sql            # 初始資料
├── 20251025101010_setup_row_level_security.sql       # RLS 設定
├── ...
└── 20251108133713_cleanup_deprecated_functions_jo.sql # 清理棄用函數
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
| `DEPRECATED_FUNCTIONS_EVALUATION.md` | 棄用函數評估報告 | ⭐⭐⭐ |
| `CLEANUP_GUIDE.md` | 清理棄用函數操作指南 | ⭐⭐⭐ |
| `20251109000000_cleanup_deprecated_functions_jo.sql` | 清理棄用函數 migration | ⭐⭐⭐ |

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

#### 清理與優化 (2025-11-09)
- ⭐ `20251109000000_cleanup_deprecated_functions_jo.sql` - 清理棄用函數

## 🔧 Conversations & Messages 功能

### 目前可用的 RPC 函數

| 函數名稱 | 功能 | 狀態 |
|---------|------|------|
| `get_user_conversations()` | 取得使用者對話列表 | ✅ 最新版 |
| `get_conversation_messages()` | 取得對話訊息 | ✅ 最新版 |
| `send_message()` | 發送訊息 | ✅ 最新版 |
| `mark_messages_as_read()` | 標記已讀 | ✅ 已優化 |
| `create_or_get_conversation()` | 建立/取得對話 | ✅ 最新版 |
| `get_unread_message_count()` | 取得未讀數量 | ✅ 已優化 |
| `delete_conversation()` | 軟刪除對話 | ✅ 新功能 |
| `restore_conversation()` | 恢復對話 | ✅ 新功能 |
| `delete_message()` | 軟刪除訊息 | ✅ 新功能 |
| `cleanup_deleted_conversations()` | 清理已刪除對話 | ✅ 維護用 |
| `get_conversations_by_ids()` | 批次取得對話 | ✅ 新功能 |

### 已棄用的函數 ❌

| 舊函數簽名 | 被取代於 | 狀態 |
|-----------|---------|------|
| `get_user_conversations(INT, INT)` | `get_user_conversations(INT, INT, TEXT, BOOLEAN)` | 🗑️ 已刪除 |
| `get_conversation_messages(BIGINT, INT, INT)` | `get_conversation_messages(BIGINT, INT, INT, BOOLEAN)` | 🗑️ 已刪除 |

**詳細資訊請參考:** `DEPRECATED_FUNCTIONS_EVALUATION.md`

## ⚠️ 重要注意事項

### 執行清理 Migration 前

1. **備份資料庫** 💾
   ```bash
   supabase db dump -f backup_$(date +%Y%m%d).sql
   ```

2. **更新前端程式碼** 🔄
   確保不再使用舊版本函數簽名

3. **先在測試環境測試** 🧪
   驗證無誤後再部署到生產環境

**詳細步驟請參考:** `CLEANUP_GUIDE.md`

### 軟刪除資料維護

建議定期執行清理，避免軟刪除資料無限增長：

```sql
-- 清理 30 天前雙方都刪除的對話
SELECT public.cleanup_deleted_conversations(30);
```

可以使用 Supabase Edge Function 配合 Cron Job 自動執行。

## 📊 驗證工具

### 檢查函數清單

```sql
-- 查看所有對話相關函數
SELECT * FROM public.conversation_functions_inventory
ORDER BY function_name;
```

### 檢查資料完整性

```sql
-- 執行完整性檢查
SELECT * FROM public.check_conversation_data_integrity();
```

### 監控軟刪除資料量

```sql
-- 查看軟刪除統計
SELECT
    '對話' as type,
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE deleted_by_buyer_at IS NOT NULL OR deleted_by_seller_at IS NOT NULL) as deleted
FROM public.conversations
UNION ALL
SELECT
    '訊息' as type,
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE deleted_at IS NOT NULL) as deleted
FROM public.conversation_messages;
```

## 🐛 故障排除

### Migration 執行失敗

```bash
# 查看詳細錯誤
supabase db push --debug

# 重置資料庫（警告：會刪除所有資料）
supabase db reset
```

### 檢查遠端與本地差異

```bash
# 比較本地與遠端
supabase db diff

# 產生 migration 來同步差異
supabase db diff --schema public | supabase migration new sync_schema
```

### 回滾 Migration

```sql
-- 手動回滾（需要自己寫回滾邏輯）
-- Supabase 不支援自動回滾，建議從備份恢復
psql $DATABASE_URL < backup_file.sql
```

## 📖 相關資源

### 官方文件
- [Supabase Migrations 文件](https://supabase.com/docs/guides/cli/local-development#database-migrations)
- [PostgreSQL 官方文件](https://www.postgresql.org/docs/)

### 專案文件
- **棄用函數評估報告:** `DEPRECATED_FUNCTIONS_EVALUATION.md`
- **清理操作指南:** `CLEANUP_GUIDE.md`

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
**最後更新:** 2024-11-09  
**版本:** 1.0