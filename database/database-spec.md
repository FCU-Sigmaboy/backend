# FCU Sigma 生態交換平台 - 資料庫規格文件

## 版本資訊
- **當前版本**: v2.0 (2025-11-07)
- **重要變更**: 移除 `items.location_id`,改用 `items.user_id` 關聯使用者主要地點

## 概述
本文件描述 FCU Sigma 生態交換平台的完整資料庫架構,採用 PostgreSQL + PostGIS 技術棧,並整合 Supabase 的認證與儲存功能。

## 系統特色
- **地理位置功能**: 使用 PostGIS 擴展支援地理位置計算
- **碳足跡追蹤**: 每個物品都有碳排放價值，促進環保意識
- **點數經濟系統**: 基於點數的交易機制
- **社交功能**: 追蹤、收藏、評價系統
- **即時通訊**: 買賣雙方聊天功能

## 資料庫擴展
```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";    -- UUID 生成
CREATE EXTENSION IF NOT EXISTS "postgis";      -- 地理空間功能
```

---

## 核心資料表架構

### 第一層：基礎資料表

#### 1. users (使用者主表)
**用途**: 儲存使用者基本資訊與評價
```sql
CREATE TABLE public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nickname VARCHAR(50) NOT NULL UNIQUE,                    -- 使用者暱稱
    profile_picture_url TEXT,                                -- 頭像 URL
    avg_rating NUMERIC(3, 2) DEFAULT 0.00,                   -- 平均評價 (0-5)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

#### 2. main_categories (主分類表)
**用途**: 物品的主要分類系統
```sql
CREATE TABLE public.main_categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,                        -- 分類名稱
    icon TEXT,                                               -- 圖示 (後加)
    color TEXT,                                              -- 顏色 (後加)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**預設分類**:
- 電子產品, 服飾配件, 家居用品, 書籍文具, 運動休閒, 美妝保養, 玩具遊戲, 其他

### 第二層：依賴基礎表的資料表

#### 3. profiles (使用者詳細資料)
**用途**: 儲存使用者的私人資訊與統計數據
```sql
CREATE TABLE public.profiles (
    user_id UUID PRIMARY KEY,                               -- FK to users.id
    balance INTEGER NOT NULL DEFAULT 0,                     -- 點數餘額
    carbon_saved_kg NUMERIC(10, 2) NOT NULL DEFAULT 0.00,   -- 累計減碳量(kg)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);
```

#### 4. locations (使用者地點表)
**用途**: 儲存使用者的地理位置資訊,支援多地點

**⭐ Migration v2.0 重要說明**:
- 物品不再直接關聯 `location_id`
- 物品透過 `items.user_id` 自動使用使用者的主要地點 (`is_primary=true`)
- 使用者更改主要地點時,所有物品自動使用新地點

```sql
CREATE TABLE public.locations (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,                                  -- FK to users.id
    coordinates GEOGRAPHY(Point, 4326) NOT NULL,            -- PostGIS 地理座標
    type VARCHAR(50) CHECK (type IN ('家', '公司', '其他')),
    is_primary BOOLEAN NOT NULL DEFAULT false,              -- 是否為主要地點 ⭐ 關鍵欄位
    formatted_address TEXT,                                 -- 格式化地址
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);
```

**索引**:
```sql
CREATE INDEX idx_locations_user_id_primary ON locations(user_id, is_primary);
```

#### 5. sub_categories (子分類表)
**用途**: 物品的詳細分類與預設碳足跡
```sql
CREATE TABLE public.sub_categories (
    id SERIAL PRIMARY KEY,
    main_category_id INTEGER NOT NULL,                      -- FK to main_categories.id
    name VARCHAR(50) NOT NULL,                              -- 子分類名稱
    default_carbon_value NUMERIC(10, 2) NOT NULL DEFAULT 0.00, -- 預設碳價值
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (main_category_id) REFERENCES public.main_categories(id) ON DELETE RESTRICT
);
```

### 第三層：核心業務表

#### 6. items (物品表) ⭐ v2.0 已更新
**用途**: 系統核心,儲存所有待交換物品

**🔄 Migration v2.0 變更 (2025-11-07)**:
- ❌ 移除 `location_id` 欄位和外鍵約束
- ✅ 物品位置透過 `user_id` 自動關聯使用者的主要地點
- ✅ 架構: `items.user_id → users.id → locations.user_id (is_primary=true)`

```sql
CREATE TABLE public.items (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,                                  -- 物品擁有者 ⭐ 同時用於關聯地點
    sub_category_id INTEGER NOT NULL,                       -- 物品分類
    -- ❌ location_id BIGINT NOT NULL,                      -- 已移除 (v2.0)
    title VARCHAR(50) NOT NULL,                             -- 物品標題
    description TEXT,                                       -- 詳細描述
    condition VARCHAR(20) NOT NULL                          -- 物品狀況
        CHECK (condition IN ('全新', '近全新', '良好', '普通', '需修理')),
    listing_status BOOLEAN NOT NULL DEFAULT true,          -- 是否上架
    price INTEGER NOT NULL DEFAULT 0,                      -- 價格(點數)
    carbon_value NUMERIC(10, 2) NOT NULL DEFAULT 0.00,     -- 碳價值
    image_urls TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],    -- 圖片 URLs 陣列
    tags TEXT[] DEFAULT ARRAY[]::TEXT[],                   -- 標籤陣列
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
    FOREIGN KEY (sub_category_id) REFERENCES public.sub_categories(id) ON DELETE RESTRICT
    -- ❌ FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE RESTRICT  -- 已移除 (v2.0)
);
```

**地點查詢方式**:
```sql
-- 取得物品的地點資訊 (透過使用者的主要地點)
SELECT i.*, l.formatted_address, l.coordinates
FROM items i
LEFT JOIN locations l ON i.user_id = l.user_id AND l.is_primary = true
WHERE i.id = ?;
```

### 第四層：交易與互動功能

#### 7. transactions (交易表)
**用途**: 記錄所有交易流程
```sql
CREATE TABLE public.transactions (
    id BIGSERIAL PRIMARY KEY,
    item_id BIGINT NOT NULL UNIQUE,                        -- 每件物品只能交易一次
    giver_id UUID NOT NULL,                                -- 贈送者
    receiver_id UUID NOT NULL,                             -- 接收者
    points_amount INTEGER NOT NULL,                        -- 交易點數
    carbon_amount_kg NUMERIC(10, 2) NOT NULL,              -- 減碳量
    transaction_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (transaction_status IN ('pending', 'confirmed', 'in_progress', 'completed', 'cancelled')),
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE RESTRICT,
    FOREIGN KEY (giver_id) REFERENCES public.users(id) ON DELETE RESTRICT,
    FOREIGN KEY (receiver_id) REFERENCES public.users(id) ON DELETE RESTRICT,
    CHECK (giver_id != receiver_id)
);
```

**交易狀態流程**:
`pending` → `confirmed` → `in_progress` → `completed`/`cancelled`

#### 8. conversations (聊天室表)
**用途**: 買賣雙方的對話管理
```sql
CREATE TABLE public.conversations (
    id BIGSERIAL PRIMARY KEY,
    item_id BIGINT NOT NULL,                               -- 關聯物品
    buyer_id UUID NOT NULL,                               -- 買家
    seller_id UUID NOT NULL,                              -- 賣家
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE,
    FOREIGN KEY (buyer_id) REFERENCES public.users(id) ON DELETE CASCADE,
    FOREIGN KEY (seller_id) REFERENCES public.users(id) ON DELETE CASCADE,
    UNIQUE(item_id, buyer_id, seller_id)                  -- 每組合只能有一個對話
);
```

#### 9. following (追蹤關係表)
**用途**: 使用者間的追蹤關係
```sql
CREATE TABLE public.following (
    follower_id UUID NOT NULL,                            -- 追蹤者
    following_id UUID NOT NULL,                           -- 被追蹤者
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, following_id),
    FOREIGN KEY (follower_id) REFERENCES public.users(id) ON DELETE CASCADE,
    FOREIGN KEY (following_id) REFERENCES public.users(id) ON DELETE CASCADE,
    CHECK (follower_id != following_id)
);
```

#### 10. favorites (收藏表)
**用途**: 使用者的物品收藏功能
```sql
CREATE TABLE public.favorites (
    user_id UUID NOT NULL,                                -- 收藏者
    item_id BIGINT NOT NULL,                              -- 收藏物品
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, item_id),
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE
);
```

### 第五層：依賴交易的功能表

#### 11. point_logs (點數記錄表)
**用途**: 追蹤所有點數變動記錄
```sql
CREATE TABLE public.point_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,                                -- 點數擁有者
    amount INTEGER NOT NULL,                              -- 變動量(正負數)
    type VARCHAR(50) NOT NULL CHECK (type IN (
        'transaction_income',    -- 交易收入
        'transaction_expense',   -- 交易支出
        'daily_login',          -- 每日登入
        'quest_reward',         -- 任務獎勵
        'initial_gift',         -- 初始贈送
        'admin_adjustment'      -- 管理員調整
    )),
    transaction_id BIGINT,                                -- 關聯交易(可選)
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
    FOREIGN KEY (transaction_id) REFERENCES public.transactions(id) ON DELETE SET NULL
);
```

#### 12. ratings (評價表)
**用途**: 交易完成後的雙向評價系統
```sql
CREATE TABLE public.ratings (
    id BIGSERIAL PRIMARY KEY,
    transaction_id BIGINT NOT NULL,                       -- 關聯交易
    reviewer_id UUID NOT NULL,                           -- 評價者
    reviewed_user_id UUID NOT NULL,                      -- 被評價者
    score SMALLINT NOT NULL CHECK (score >= 1 AND score <= 5), -- 評分 1-5
    comment TEXT,                                         -- 評價內容
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (transaction_id) REFERENCES public.transactions(id) ON DELETE CASCADE,
    FOREIGN KEY (reviewer_id) REFERENCES public.users(id) ON DELETE CASCADE,
    FOREIGN KEY (reviewed_user_id) REFERENCES public.users(id) ON DELETE CASCADE,
    UNIQUE(transaction_id, reviewer_id)                   -- 每個交易每人只能評價一次
);
```

#### 13. conversation_messages (聊天訊息表)
**用途**: 儲存對話中的所有訊息
```sql
CREATE TABLE public.conversation_messages (
    id BIGSERIAL PRIMARY KEY,
    conversation_id BIGINT NOT NULL,                      -- 所屬對話
    sender_id UUID NOT NULL,                             -- 發送者
    content TEXT NOT NULL,                               -- 訊息內容
    is_read BOOLEAN NOT NULL DEFAULT false,              -- 已讀狀態
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE,
    FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE CASCADE
);
```

---

## 核心 RPC 函數

### 1. search_items() - 物品搜尋 (v6.0) ⭐
**功能**: 根據多種條件搜尋物品,支援地理位置排序

**🔄 Migration v2.0 更新**:
- ✅ 自動使用買家的主要地點計算距離
- ✅ 自動使用賣家的主要地點 (透過 `items.user_id`)
- ✅ 不再需要傳遞經緯度參數

**參數**:
- `p_distance_range_km`: 搜尋半徑 (公里)
- `p_main_category_id`: 主分類 ID
- `p_sub_category_id`: 子分類 ID  
- `p_keyword`: 關鍵字搜尋
- `p_user_id`: 指定使用者
- `p_page`, `p_size`: 分頁參數
- `p_sort_by`: 排序欄位 (`created_at`, `price`, `distance`)
- `p_sort_direction`: 排序方向 (`asc`, `desc`)

**回傳**: 物品清單含距離、收藏數、使用者資訊

**距離計算邏輯**:
```sql
-- 買家位置: auth.uid() → locations (is_primary=true)
-- 賣家位置: items.user_id → locations (is_primary=true)
-- 距離: ST_Distance(買家座標, 賣家座標)
```

### 2. get_my_favorite_items() - 我的收藏 (v2.0) ⭐
**功能**: 取得當前使用者的收藏物品

**🔄 Migration v2.0 更新**:
- ✅ 自動使用當前使用者的主要地點計算距離
- ✅ 自動使用賣家的主要地點 (透過 `items.user_id`)

**特色**: 自動計算距離,包含收藏時間

### 3. get_my_items() - 我的物品
**功能**: 取得當前使用者發布的物品
**特色**: 包含收藏統計

### 4. get_item_details_with_location() - 物品詳情 (v3.0) ⭐
**功能**: 取得單一物品的完整詳情

**🔄 Migration v2.0 更新**:
- ✅ 使用 `items.user_id` 關聯賣家位置
- ✅ 完整的隱私保護機制
- ✅ 支援未登入用戶瀏覽基本資訊

**參數**:
- `p_item_id`: 物品 ID

**回傳**: 完整物品資訊含地點、距離、賣家資訊等

### 5. create_item() - 刊登物品 (v2.0) ⭐
**功能**: 建立新物品

**🔄 Migration v2.0 重大變更**:
- ❌ 移除 `p_user_location_id` 參數
- ✅ 自動使用使用者的主要地點
- ✅ 刊登前會檢查使用者是否有設定地點

**參數**:
- `p_sub_category_id`: 子分類 ID
- ~~`p_user_location_id`~~: ❌ 已移除 (v2.0)
- `p_title`: 物品標題
- `p_description`: 物品描述
- `p_condition`: 物品狀況
- `p_price`: 價格(點數)
- `p_carbon_value`: 碳價值 (可選)
- `p_image_urls`: 圖片 URLs (可選)
- `p_tags`: 標籤 (可選)

**錯誤處理**:
- 如果使用者沒有任何地點,會回傳錯誤: "請先在個人資料中設定地點後再刊登物品"

---

## 資料庫安全機制

### Row Level Security (RLS)
**狀態**: 目前為 Demo 環境已停用，正式環境需啟用

**核心原則**:
- **使用者資料**: 只能存取自己的私人資料
- **物品資料**: 公開物品所有人可見，私人物品只有擁有者可見
- **交易資料**: 只有交易雙方可以存取
- **聊天資料**: 只有對話參與者可以存取
- **分類資料**: 完全公開

### Storage 權限
**Buckets**:
- `avatars`: 使用者頭像儲存
- `items`: 物品圖片儲存

**權限結構**:
- 所有人可讀取
- 只有檔案擁有者可修改/刪除
- 路徑結構: `{bucket}/{user_id}/{filename}`

---

## 索引優化策略

### 主要索引
```sql
-- 地理位置查詢
CREATE INDEX idx_locations_coordinates ON locations USING GIST(coordinates);
CREATE INDEX idx_locations_user_id_primary ON locations(user_id, is_primary);  -- ⭐ v2.0 新增

-- 物品搜尋
CREATE INDEX idx_items_listing_status ON items(listing_status);
CREATE INDEX idx_items_created_at ON items(created_at DESC);
CREATE INDEX idx_items_tags ON items USING GIN(tags);

-- 使用者關聯 (⭐ v2.0 重要: items.user_id 同時用於地點關聯)
CREATE INDEX idx_items_user_id ON items(user_id);
CREATE INDEX idx_favorites_user_id ON favorites(user_id);
CREATE INDEX idx_point_logs_user_id ON point_logs(user_id);
```

**索引說明**:
- `idx_locations_user_id_primary`: 用於快速查詢使用者的主要地點,這是 v2.0 的關鍵索引
- `idx_items_user_id`: 除了關聯使用者外,也用於 JOIN locations 表查詢物品地點

---

## 觸發器系統

### 自動 updated_at 更新
所有主要資料表都配置自動更新 `updated_at` 欄位的觸發器：

```sql
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

---

## 資料完整性約束

### 重要約束條件
1. **自我關聯防護**: 使用者不能追蹤自己、不能與自己交易
2. **唯一性約束**: 每件物品只能交易一次
3. **評分範圍**: 評價分數限制在 1-5 分
4. **餘額檢查**: 點數餘額不能為負數
5. **碳價值檢查**: 碳足跡值必須為正數

### 外鍵關聯
- `CASCADE`: 使用者刪除時，相關資料一併刪除
- `RESTRICT`: 分類等基礎資料有關聯時不可刪除
- `SET NULL`: 交易刪除時，點數記錄保留但斷開關聯

---

## 效能考量

### 查詢優化
1. **地理位置查詢**: 使用 PostGIS 的 GIST 索引
2. **標籤搜尋**: 使用 GIN 索引支援陣列搜尋
3. **分頁查詢**: 所有列表 API 都支援分頁
4. **複合查詢**: 使用 CTE 優化複雜關聯查詢

### 資料量預估
- **使用者**: 10K+ 
- **物品**: 100K+
- **交易**: 50K+
- **訊息**: 1M+

---

## 開發注意事項

### Supabase 整合
1. **認證**: 使用 `auth.uid()` 獲取當前使用者
2. **Storage**: 配合 Supabase Storage API 使用
3. **即時更新**: 可配置 Realtime 監聽

### TypeScript 類型
建議根據資料表結構生成對應的 TypeScript 類型定義，確保前後端資料一致性。

### 遷移管理  
所有資料庫變更都應透過 migration 檔案管理，確保版本控制與部署一致性。

---

## Migration 歷程

### v2.0 (2025-11-07) - 移除 items.location_id
**變更內容**:
- 移除 `items.location_id` 欄位和相關外鍵約束
- 物品改為透過 `items.user_id` 關聯使用者的主要地點
- 更新所有相關 RPC 函數 (search_items v6.0, get_my_favorite_items v2.0, get_item_details_with_location v3.0, create_item v2.0)
- 新增 `idx_locations_user_id_primary` 索引

**優勢**:
- 簡化資料模型,物品自動使用使用者的主要地點
- 使用者更改主要地點時,所有物品自動更新
- 減少資料不一致的可能性
- 更符合業務邏輯

**相關文件**:
- [MIGRATION_GUIDE_20251107.md](../supabase/migrations/MIGRATION_GUIDE_20251107.md)
- [QUICK_REFERENCE.md](../supabase/migrations/QUICK_REFERENCE.md)

---

## 未來擴展預留

### 可能的功能擴展
1. **多語言支援**: 分類名稱國際化
2. **推薦系統**: 基於使用者行為的物品推薦
3. **報告系統**: 不當內容檢舉機制
4. **統計分析**: 碳足跡統計、交易分析
5. **通知系統**: 交易狀態、新訊息通知

### 效能擴展
1. **讀取分離**: 查詢密集的功能可考慮讀寫分離
2. **快取層**: Redis 快取熱門搜尋結果
3. **全文搜索**: 整合 Elasticsearch 提升搜尋體驗