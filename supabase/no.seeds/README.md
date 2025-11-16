# 測試種子資料說明文件

## 版本更新註釋
- 2025-11-15: 更新測試種子資料以符合當前資料庫設計

## 概述

此目錄包含用於開發和測試環境的種子資料。這些資料模擬真實使用情境，幫助開發者測試應用程式的各項功能。

## 資料結構

### 檔案列表

1. **01_users.sql** - 使用者基礎資料
2. **02_profiles.sql** - 使用者詳細資料（餘額、碳足跡等）
3. **03_locations.sql** - 使用者地點資料
4. **04_categories.sql** - 主分類與子分類資料
5. **05_items.sql** - 物品資料
6. **06_interactions.sql** - 互動資料（對話、追蹤、收藏）
7. **seed.sql** - 整合執行檔案

## 資料內容

### 使用者 (6位)

| 使用者ID | 暱稱 | 評分 | 餘額 | 碳足跡 |
|---------|------|------|------|--------|
| 488a4712... | Tao | 4.5 | 100 | 15.25 kg |
| cdf0fa87... | Yo | 4.8 | 120 | 22.10 kg |
| 7140056b... | Lee | 4.2 | 80 | 10.50 kg |
| 9b900884... | Lin | 4.7 | 150 | 30.00 kg |
| c8d6998b... | Liao | 4.0 | 90 | 18.70 kg |
| e773c5f7... | Chen | 4.6 | 110 | 25.40 kg |

### 地點 (10個)

每位使用者可擁有：
- **最多 1 個「家」地點**
- **最多 1 個「公司」地點**
- **全局只能有 1 個主要地點** (`is_primary = true`)

地點分佈：
- Tao: 家(主要) + 公司
- Yo: 家(主要) + 公司
- Lee: 公司(主要) + 家
- Lin: 家(主要)
- Liao: 公司(主要)
- Chen: 家(主要) + 公司

所有地點位於台中市不同區域。

### 分類

#### 主分類 (6個)
1. 流行服飾 🧍 (#ff6f61)
2. 鞋包配件 👜 (#e83e8c)
3. 3C 電子 📱 (#007bff)
4. 家電用品 🏠 (#28a745)
5. 親子婦幼 💕 (#6f42c1)
6. 生活娛樂 🎮 (#fd7e14)

#### 子分類 (36個)
每個主分類包含 6 個子分類，涵蓋常見商品類型。

### 物品 (36件)

- 每位使用者擁有 6 件物品
- 物品狀況：全新、近全新、普通
- 價格範圍：0-400 點數
- 所有物品預設為上架狀態 (`listing_status = true`)
- 使用 `use_primary_location` 欄位指定使用主要或次要地點

### 互動資料

#### 對話 (5組)
- 5 組買賣雙方對話
- 共 11 則訊息

#### 追蹤關係 (6組)
使用者之間的追蹤網絡

#### 收藏 (12個)
每位使用者收藏 2 件物品

## 使用方式

### 方法一：使用整合檔案

```bash
# 進入專案目錄
cd backend/supabase

# 使用 psql 執行
psql -U postgres -d your_database -f no.seeds/seed.sql
```

### 方法二：使用 Supabase CLI

```bash
# 重置資料庫並載入種子資料
supabase db reset

# 或僅載入種子資料（需手動執行）
supabase db reset --db-only
```

### 方法三：逐一執行

```bash
psql -U postgres -d your_database -f no.seeds/01_users.sql
psql -U postgres -d your_database -f no.seeds/02_profiles.sql
psql -U postgres -d your_database -f no.seeds/03_locations.sql
psql -U postgres -d your_database -f no.seeds/04_categories.sql
psql -U postgres -d your_database -f no.seeds/05_items.sql
psql -U postgres -d your_database -f no.seeds/06_interactions.sql
```

## 重要特性

### 1. 地點約束
- ✅ 每位使用者最多 2 個地點（家 + 公司）
- ✅ 每種類型只能有 1 個
- ✅ 全局只有 1 個主要地點
- ❌ 不再支援「其他」類型

### 2. 物品地點關聯
- ✅ 不使用 `location_id` 外鍵
- ✅ 使用 `use_primary_location` 布林值
  - `true` = 使用主要地點
  - `false` = 使用次要地點
- ✅ 透過 JOIN `locations` 表動態獲取地點資訊

### 3. 分類系統
- ✅ 主分類包含 `icon` 和 `color` 欄位
- ✅ 子分類包含預設碳排放值

### 4. 資料完整性
- 所有資料使用 `ON CONFLICT DO NOTHING` 避免重複插入
- 序列值自動重設確保 ID 連續性
- 使用交易確保資料一致性

## 測試場景

此種子資料支援以下測試場景：

1. **物品搜尋** - 36 件物品涵蓋 6 大分類
2. **地理位置搜尋** - 10 個不同地點測試距離計算
3. **使用者互動** - 對話、追蹤、收藏功能
4. **物品地點切換** - 主要/次要地點使用測試
5. **多使用者場景** - 6 位使用者模擬真實互動

## 注意事項

⚠️ **僅用於開發和測試環境，請勿在生產環境使用！**

- 種子資料包含固定的 UUID，可能與實際 auth.users 不一致
- 圖片 URL 為示例連結，實際使用需替換
- 地理座標為台中市區域，可根據需求調整

## 清理資料

如需清理測試資料：

```sql
-- 清空所有表格（注意順序）
TRUNCATE TABLE conversation_messages CASCADE;
TRUNCATE TABLE conversations CASCADE;
TRUNCATE TABLE ratings CASCADE;
TRUNCATE TABLE point_logs CASCADE;
TRUNCATE TABLE transactions CASCADE;
TRUNCATE TABLE favorites CASCADE;
TRUNCATE TABLE following CASCADE;
TRUNCATE TABLE items CASCADE;
TRUNCATE TABLE locations CASCADE;
TRUNCATE TABLE profiles CASCADE;
TRUNCATE TABLE users CASCADE;
TRUNCATE TABLE sub_categories CASCADE;
TRUNCATE TABLE main_categories CASCADE;
```

## 更新歷史

### 2025-11-15
- 移除 items.location_id 欄位
- 新增 items.use_primary_location 欄位
- 更新 locations 約束：僅允許「家」和「公司」類型
- 新增 main_categories.icon 和 color 欄位
- 更新所有種子資料以符合新架構

### 2023-10-27
- 初始版本建立
- 建立基礎測試資料