# 地點與距離計算架構說明

本文件說明 Map Function 的架構設計，包括為何使用 Edge Function 與 RPC 的組合，以及它們如何協同工作實現「使用者地點儲存」和「物品距離計算」功能。

---

## 目錄

- [架構概覽](#架構概覽)
- [為什麼需要 RPC？](#為什麼需要-rpc)
- [Edge Function vs RPC 比較](#edge-function-vs-rpc-比較)
- [完整流程說明](#完整流程說明)
- [架構優勢](#架構優勢)
- [何時使用 RPC vs Edge Function](#何時使用-rpc-vs-edge-function)
- [性能優化](#性能優化)
- [未來擴展方向](#未來擴展方向)

---

## 架構概覽

### 技術選型

本專案採用 **Edge Function + RPC** 的混合架構：

| 功能 | 實作方式 | 檔案位置 |
|------|---------|---------|
| **儲存使用者地點** | Edge Function (TypeScript) | `supabase/functions/save-location/index.ts` |
| **搜尋物品並計算距離** | RPC (PL/pgSQL) | `API_Example/dbs/get_searchItems (RPC).sql` |
| **前端呼叫範例** | JavaScript | `API_Example/apis/` |

### 職責分離

```
┌─────────────────────────────────────────────────────────────┐
│                         前端應用                              │
│  - 取得使用者位置 (Geolocation API)                           │
│  - 呼叫 API 儲存地點                                          │
│  - 呼叫 API 搜尋物品                                          │
│  - 顯示物品列表與距離                                         │
└────────────┬────────────────────────────┬────────────────────┘
             │                            │
             ▼                            ▼
    ┌────────────────┐          ┌────────────────────┐
    │ Edge Function  │          │   RPC Function     │
    │ save-location  │          │   search_items     │
    │                │          │                    │
    │ - 驗證使用者   │          │ - 取得主要地點     │
    │ - 更新 primary │          │ - 計算距離 (PostGIS)│
    │ - 插入地點     │          │ - 篩選與排序       │
    └────────┬───────┘          └────────┬───────────┘
             │                            │
             └────────────┬───────────────┘
                          ▼
                  ┌───────────────┐
                  │  Supabase DB  │
                  │  - locations  │
                  │  - items      │
                  │  - users      │
                  └───────────────┘
```

---

## 為什麼需要 RPC？

### RPC 的核心優勢

#### 1. 複雜業務邏輯集中在後端

**使用 RPC 的場景**（如購買流程）：

```sql
-- 購買流程：一次 RPC 完成 7 個步驟
CREATE FUNCTION execute_purchase(p_item_id BIGINT)
RETURNS JSON AS $$
BEGIN
  -- 1. 檢查物品狀態
  -- 2. 鎖定資料列 (FOR UPDATE) - 防止併發
  -- 3. 檢查買家點數
  -- 4. 更新物品狀態
  -- 5. 扣除買家點數
  -- 6. 增加賣家點數
  -- 7. 插入交易紀錄
  -- ✅ 全部成功或全部失敗（原子性）
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

**前端只需一行**：
```javascript
const result = await supabase.rpc('execute_purchase', { p_item_id: 101 });
```

**如果不用 RPC，前端需要**：
```javascript
// ❌ 7 次獨立的資料庫操作
// ❌ 無法保證原子性！可能中途失敗導致資料不一致
// ❌ 無法防止併發問題（超賣）
```

#### 2. 資料庫級別的交易保證

```sql
-- RPC 內的所有操作要麼全部成功，要麼全部失敗
BEGIN
  UPDATE items SET listing_status = FALSE WHERE id = p_item_id;
  UPDATE profiles SET balance = balance - price WHERE user_id = buyer;
  UPDATE profiles SET balance = balance + price WHERE user_id = seller;
  INSERT INTO transactions (...) VALUES (...);
EXCEPTION WHEN OTHERS THEN
  ROLLBACK; -- 發生錯誤時自動回滾
END;
```

#### 3. 防止併發問題

```sql
-- 鎖定資料列，防止兩個人同時購買
SELECT * FROM items WHERE id = p_item_id FOR UPDATE;
```

前端無法做到這點，可能導致「超賣」問題。

#### 4. 性能優化 - 減少網路往返

```
不使用 RPC：
前端 → 資料庫 (查詢物品) → 前端
前端 → 資料庫 (查詢使用者) → 前端
前端 → 資料庫 (計算距離) → 前端
= 3 次網路往返

使用 RPC：
前端 → 資料庫 (RPC 一次完成) → 前端
= 1 次網路往返 (性能提升 3 倍)
```

#### 5. 複雜的地理計算

```sql
-- PostGIS 空間查詢在資料庫層面非常高效
SELECT ST_Distance(l1.coordinates, l2.coordinates) / 1000.0 AS distance_km
FROM locations l1, locations l2
WHERE ST_DWithin(l1.coordinates, l2.coordinates, 50000); -- 50km 內
```

前端無法高效執行這類空間查詢。

#### 6. 自動獲取登入使用者（安全性）

```sql
-- 後端自動獲取，前端無法偽造
v_current_uid UUID := auth.uid();
```

前端如果傳 `user_id` 參數，可以被惡意修改。

---

## Edge Function vs RPC 比較

### 購買流程 vs 儲存地點

| 特性 | 購買流程 (execute_purchase) | 儲存地點 (save-location) |
|------|---------------------------|------------------------|
| **需要交易保證** | ✅ 是（扣點數、下架物品、插入交易紀錄） | ❌ 否（只是單純的插入/更新） |
| **併發風險** | ✅ 高（可能超賣） | ❌ 低（只是更新自己的地點） |
| **複雜計算** | ❌ 否 | ❌ 否 |
| **多表聯合操作** | ✅ 是（3個表） | ❌ 否（只有 locations 表） |
| **適合用 RPC** | ✅ 是 | ❌ 否 |
| **適合用 Edge Function** | ❌ 否 | ✅ 是 |

### Edge Function 的優勢（適合儲存地點的場景）

#### 1. 更靈活

```typescript
// Edge Function 可以做更複雜的事情
// 1. 呼叫外部 API（例如 Google Maps API 驗證地址）
const response = await fetch('https://maps.googleapis.com/...')

// 2. 複雜的 JavaScript 邏輯
const formattedAddress = formatAddress(latitude, longitude)

// 3. 整合第三方服務
await sendNotification(user.email, '地點已儲存')
```

RPC（PL/pgSQL）無法輕鬆做到這些。

#### 2. 更容易除錯

```typescript
// Edge Function：可以用 console.log
console.error('Database insert error:', insertError)

// RPC：只能看 PostgreSQL 日誌，不方便
RAISE NOTICE 'Error: %', v_error_message;
```

#### 3. 前端呼叫方式更簡潔

```javascript
// Edge Function：統一的 functions.invoke 介面
const { data, error } = await supabase.functions.invoke('save-location', {
  body: { latitude, longitude, type, is_primary }
})

// RPC：需要用 .rpc()
const { data, error } = await supabase.rpc('save_location', {
  p_latitude: latitude,
  p_longitude: longitude,
  p_type: type,
  p_is_primary: is_primary
})
```

Edge Function 的呼叫方式更直觀（不需要 `p_` 前綴）。

---

## 完整流程說明

### 流程 1：使用者註冊並儲存地點

#### 前端呼叫

```javascript
// 前端呼叫 Edge Function
const { data } = await supabase.functions.invoke('save-location', {
  body: {
    latitude: 25.0330,
    longitude: 121.5654,
    type: '家',
    is_primary: true  // 標記為主要地點
  }
})
```

#### Edge Function 處理邏輯

```typescript
// supabase/functions/save-location/index.ts

// 1. 驗證使用者身份
const authHeader = req.headers.get('Authorization')
const token = authHeader.replace('Bearer ', '')
const { data: { user } } = await supabaseAdmin.auth.getUser(token)

// 2. 如果是主要地點，先把其他地點的 is_primary 設為 false
if (is_primary) {
  await supabaseAdmin
    .from('locations')
    .update({ is_primary: false })
    .eq('user_id', user.id)
}

// 3. 插入新地點（PostGIS POINT 格式）
const locationPoint = `POINT(${longitude} ${latitude})`
await supabaseAdmin.from('locations').insert({
  user_id: user.id,
  coordinates: locationPoint,  // PostGIS 格式
  type: type,
  is_primary: is_primary,
  formatted_address: formatted_address
})
```

#### 資料庫結構

```sql
-- locations 表結構
CREATE TABLE locations (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  coordinates GEOGRAPHY(Point, 4326),  -- PostGIS 地理點
  type VARCHAR(50),                     -- '家'、'公司'、'其他'
  is_primary BOOLEAN DEFAULT FALSE,     -- 是否為主要地點
  formatted_address TEXT,               -- 格式化地址
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

### 流程 2：搜尋物品並自動計算距離

#### 前端呼叫

```javascript
// 前端呼叫搜尋 API
import { searchItems } from './apis/get_searchItemsAPI.js'

const items = await searchItems({
  distance_range_km: 10,  // 只搜尋 10 公里內的物品
  sort_by: 'distance',    // 按距離排序
  sort_direction: 'asc'   // 由近到遠
})
```

#### RPC 自動處理距離計算

```sql
-- API_Example/dbs/get_searchItems (RPC).sql

CREATE OR REPLACE FUNCTION public.search_items(
    p_distance_range_km INT DEFAULT NULL,
    p_main_category_id INT DEFAULT NULL,
    p_sub_category_id INT DEFAULT NULL,
    p_keyword TEXT DEFAULT NULL,
    p_user_id UUID DEFAULT NULL,
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20,
    p_sort_by TEXT DEFAULT 'created_at',
    p_sort_direction TEXT DEFAULT 'desc'
)
RETURNS TABLE (
    item_id BIGINT,
    title VARCHAR(50),
    image_url TEXT,
    price INT,
    distance_km NUMERIC,  -- ✅ 自動計算的距離
    formatted_address TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    favorites_count BIGINT,
    "user" JSON
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
    v_current_uid UUID := auth.uid();  -- 自動取得當前使用者
BEGIN
    -- 1. 驗證使用者登入狀態
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入，無法執行搜尋';
    END IF;

    -- 2. 檢查使用者是否有主要地點
    IF NOT EXISTS (
        SELECT 1 FROM public.locations
        WHERE user_id = v_current_uid AND is_primary = true
    ) THEN
        RAISE NOTICE '找不到使用者的主要地點，距離計算將不可用';
    END IF;

    -- 3. 執行查詢，使用子查詢自動取得使用者位置並計算距離
    RETURN QUERY
    SELECT
        i.id AS item_id,
        i.title,
        i.image_urls[1] AS image_url,
        i.price,
        -- ✅ 使用子查詢自動取得使用者的主要地點並計算距離
        (
            SELECT ROUND((ST_Distance(
                l.coordinates,  -- 物品的地點
                (SELECT coordinates
                 FROM public.locations
                 WHERE user_id = v_current_uid  -- 自動取得當前登入使用者
                   AND is_primary = true        -- 只取主要地點
                 LIMIT 1)
            ) / 1000.0)::numeric, 3)  -- 轉換為公里，保留 3 位小數
        ) AS distance_km,
        l.formatted_address,
        i.created_at,
        i.updated_at,
        (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
        json_build_object(
            'id', i.user_id,
            'nickname', u.nickname,
            'profile_picture_url', u.profile_picture_url
        ) AS "user"
    FROM public.items i
    LEFT JOIN public.users u ON i.user_id = u.id
    LEFT JOIN public.locations l ON i.location_id = l.id
    WHERE i.listing_status = TRUE
      -- ✅ 距離篩選條件（只顯示 X 公里內的物品）
      AND (p_distance_range_km IS NULL OR
           (SELECT ROUND((ST_Distance(l.coordinates,
                                     (SELECT coordinates FROM public.locations
                                      WHERE user_id = v_current_uid AND is_primary = true
                                      LIMIT 1)
                         ) / 1000.0)::numeric, 3)
           ) <= p_distance_range_km)
      -- 其他篩選條件...
    -- ✅ 按距離排序
    ORDER BY distance_km ASC NULLS LAST;
END;
$$;
```

#### 關鍵邏輯說明

1. **自動取得使用者位置**：RPC 自動從 `locations` 表取得「當前使用者的主要地點」
2. **PostGIS 計算距離**：使用 `ST_Distance` 計算兩個地理點之間的距離（米）
3. **單位轉換**：除以 1000 轉換為公里
4. **距離篩選**：支援只顯示 X 公里內的物品
5. **距離排序**：支援按距離由近到遠或由遠到近排序

#### 前端收到的回傳資料

```json
[
  {
    "item_id": 101,
    "title": "（全新）IKEA 檯燈",
    "image_url": "https://.../item101_cover.jpg",
    "price": 500,
    "distance_km": "1.254",  // ✅ 自動計算的距離
    "formatted_address": "台中市西屯區福星路",
    "created_at": "2025-10-18T10:30:00.123+00:00",
    "updated_at": "2025-10-18T10:30:00.123+00:00",
    "favorites_count": 15,
    "user": {
      "id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
      "nickname": "Joseph",
      "profile_picture_url": "https://.../joseph.jpg"
    }
  }
]
```

---

## 架構優勢

### 1. 使用者體驗優秀

```javascript
// ✅ 前端不需要傳入經緯度！RPC 自動取得
const items = await searchItems({
  distance_range_km: 5,
  sort_by: 'distance'
})
// 回傳的每個物品都包含 distance_km
```

前端不需要：
- ❌ 取得使用者位置
- ❌ 手動計算距離
- ❌ 擔心精度問題

RPC 自動處理一切！

### 2. 性能優化到位

已建立關鍵索引確保查詢效率：

```sql
-- GIST 索引：加速地理位置查詢
CREATE INDEX idx_locations_coordinates
ON public.locations USING GIST (coordinates);

-- 複合索引：快速查找主要地點
CREATE INDEX idx_locations_user_primary
ON public.locations (user_id, is_primary)
WHERE is_primary = true;

-- GIN 索引：加速標籤搜尋
CREATE INDEX idx_items_tags
ON public.items USING GIN (tags);

-- 常用篩選欄位索引
CREATE INDEX idx_items_listing_status ON public.items (listing_status);
CREATE INDEX idx_items_sub_category_id ON public.items (sub_category_id);
```

這確保了：
- ✅ 距離計算非常快速
- ✅ 即使有上萬筆物品，查詢也在毫秒級完成

### 3. 支援靈活的搜尋條件

```javascript
// 案例 1：搜尋 10 公里內的二手家具
await searchItems({
  distance_range_km: 10,
  main_category_id: 2,  // 居家生活
  sort_by: 'distance'
})

// 案例 2：搜尋 5 公里內的便宜物品
await searchItems({
  distance_range_km: 5,
  sort_by: 'price',
  sort_direction: 'asc'
})

// 案例 3：搜尋關鍵字「IKEA」，按距離排序
await searchItems({
  keyword: 'IKEA',
  sort_by: 'distance'
})

// 案例 4：搜尋特定使用者的物品
await searchItems({
  user_id: 'uuid-here',
  sort_by: 'created_at'
})
```

### 4. 安全性保證

- ✅ Edge Function 使用 JWT 驗證使用者身份
- ✅ RPC 使用 `auth.uid()` 自動取得當前使用者，無法偽造
- ✅ RLS (Row Level Security) 策略確保資料隔離
- ✅ `SECURITY DEFINER` 確保權限控制正確

---

## 何時使用 RPC vs Edge Function

### ✅ 應該使用 RPC 的情境

1. **需要原子性交易**
   - 購買流程（多個資料表同時更新）
   - 轉帳操作
   - 庫存管理

2. **複雜的業務邏輯**
   - 多步驟驗證
   - 複雜計算（距離、評分、推薦）
   - 條件分支很多

3. **需要高性能**
   - 大量資料聚合
   - 地理空間查詢（PostGIS）
   - 複雜的 JOIN 操作

4. **安全性要求高**
   - 需要在後端驗證權限
   - 敏感操作（金額、點數）
   - 不能讓前端直接存取某些資料

### ✅ 應該使用 Edge Function 的情境

1. **需要整合外部 API**
   - Google Maps API
   - 第三方服務
   - Webhook 處理

2. **複雜的 JavaScript 邏輯**
   - 資料格式轉換
   - 複雜的驗證邏輯
   - 需要使用 npm 套件

3. **簡單的 CRUD 操作**
   - 單一資料表的插入/更新
   - 不需要交易保證
   - 不需要複雜的資料庫查詢

4. **需要靈活性**
   - 未來可能需要改動邏輯
   - 需要頻繁迭代
   - 除錯需求高

### ❌ 不需要 RPC 的情境

1. **簡單的 CRUD 操作**
   ```javascript
   // 直接用 Supabase Client 就好
   await supabase.from('items').select('*');
   await supabase.from('favorites').insert({ item_id });
   ```

2. **只讀取資料，不修改**
   ```javascript
   // 取得分類清單
   await supabase.from('categories').select('*, sub_categories(*)');
   ```

3. **前端邏輯為主**
   - UI 狀態管理
   - 資料格式轉換
   - 簡單過濾排序

---

## 性能優化

### 索引策略

```sql
-- 1. 地理空間索引（最重要！）
CREATE INDEX idx_locations_coordinates
ON public.locations USING GIST (coordinates);

-- 2. 主要地點查詢優化
CREATE INDEX idx_locations_user_primary
ON public.locations (user_id, is_primary)
WHERE is_primary = true;

-- 3. 物品篩選優化
CREATE INDEX idx_items_listing_status ON public.items (listing_status);
CREATE INDEX idx_items_sub_category_id ON public.items (sub_category_id);

-- 4. 標籤搜尋優化
CREATE INDEX idx_items_tags ON public.items USING GIN (tags);
```

### 查詢優化技巧

1. **使用子查詢快取使用者位置**
   ```sql
   -- 在 SELECT 中使用子查詢，PostgreSQL 會自動優化
   (SELECT coordinates FROM locations
    WHERE user_id = v_current_uid AND is_primary = true
    LIMIT 1)
   ```

2. **使用 LIMIT 限制結果數量**
   ```sql
   -- 分頁查詢，避免一次取得太多資料
   LIMIT p_size OFFSET v_offset;
   ```

3. **使用 PostGIS 的空間索引**
   ```sql
   -- ST_DWithin 會使用 GIST 索引
   WHERE ST_DWithin(l1.coordinates, l2.coordinates, 50000);
   ```

---

## 未來擴展方向

### 1. 反向地理編碼（推薦！）

在 Edge Function 中加入 Google Maps API，自動從經緯度取得地址：

```typescript
// supabase/functions/save-location/index.ts

// 自動從經緯度取得地址
const response = await fetch(
  `https://maps.googleapis.com/maps/api/geocode/json?` +
  `latlng=${latitude},${longitude}&key=${GOOGLE_MAPS_API_KEY}&language=zh-TW`
)
const { results } = await response.json()
const formatted_address = results[0]?.formatted_address || null

// 儲存到資料庫
await supabaseAdmin.from('locations').insert({
  user_id: user.id,
  coordinates: `POINT(${longitude} ${latitude})`,
  type,
  is_primary,
  formatted_address  // ✅ 自動取得的地址
})
```

這樣使用者就不需要手動輸入地址！

### 2. 多地點支援與切換

架構已經支援使用者儲存多個地點：

```javascript
// 使用者可以儲存家、公司、學校等多個地點
await saveLocation({
  latitude: 25.0330,
  longitude: 121.5654,
  type: '家',
  is_primary: true
})

await saveLocation({
  latitude: 25.0500,
  longitude: 121.5700,
  type: '公司',
  is_primary: false
})

await saveLocation({
  latitude: 25.0400,
  longitude: 121.5600,
  type: '學校',
  is_primary: false
})
```

**未來可以讓使用者在搜尋時「切換基準地點」**：

```javascript
// 前端提供下拉選單讓使用者選擇基準地點
// 然後更新該地點為主要地點
await supabase
  .from('locations')
  .update({ is_primary: true })
  .eq('id', selectedLocationId)
  .eq('user_id', user.id)
```

### 3. 地圖視覺化

在前端整合 Google Maps，顯示：

```javascript
// 使用者位置（藍色標記）
new google.maps.Marker({
  position: { lat: userLat, lng: userLng },
  map: map,
  icon: 'http://maps.google.com/mapfiles/ms/icons/blue-dot.png'
})

// 物品位置（紅色標記）
items.forEach(item => {
  new google.maps.Marker({
    position: { lat: item.latitude, lng: item.longitude },
    map: map,
    title: item.title
  })
})

// 距離圈（10km 半徑）
new google.maps.Circle({
  center: { lat: userLat, lng: userLng },
  radius: 10000,  // 10km
  map: map,
  fillColor: '#4285F4',
  fillOpacity: 0.1
})
```

### 4. 使用 Database Trigger 簡化 Edge Function

目前 Edge Function 需要手動處理 `is_primary` 邏輯，可以改用 Trigger 自動處理：

```sql
-- 建立 Trigger 自動處理 is_primary
CREATE OR REPLACE FUNCTION handle_primary_location()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_primary = TRUE THEN
    -- 將該使用者的其他地點設為 non-primary
    UPDATE locations
    SET is_primary = FALSE
    WHERE user_id = NEW.user_id AND id != NEW.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_primary_location
BEFORE INSERT OR UPDATE ON locations
FOR EACH ROW
EXECUTE FUNCTION handle_primary_location();
```

然後 Edge Function 可以簡化為：

```typescript
// 只需要插入，Trigger 會自動處理 is_primary
await supabaseAdmin.from('locations').insert({
  user_id: user.id,
  coordinates: `POINT(${longitude} ${latitude})`,
  type,
  is_primary,
  formatted_address
})
```

### 5. 距離快取機制（效能優化）

對於熱門物品，可以定期計算並快取距離：

```sql
-- 建立快取表
CREATE TABLE location_distance_cache (
  user_id UUID,
  item_id BIGINT,
  distance_km NUMERIC,
  calculated_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, item_id)
);

-- 定期更新快取（可以用 pg_cron）
SELECT cron.schedule('update-distance-cache', '0 */6 * * *', $$
  INSERT INTO location_distance_cache (user_id, item_id, distance_km)
  SELECT u.id, i.id, ST_Distance(...) / 1000.0
  FROM users u, items i
  ON CONFLICT (user_id, item_id) DO UPDATE SET
    distance_km = EXCLUDED.distance_km,
    calculated_at = NOW();
$$);
```

### 6. 推薦系統整合

結合距離和使用者偏好提供智慧推薦：

```sql
-- 推薦 RPC：結合距離、收藏數、分類偏好
CREATE FUNCTION get_recommended_items(p_limit INT DEFAULT 20)
RETURNS TABLE (...) AS $$
BEGIN
  RETURN QUERY
  SELECT ...
  FROM items i
  WHERE distance_km < 10  -- 10km 內
    AND sub_category_id IN (
      -- 使用者常收藏的分類
      SELECT sub_category_id FROM favorites
      WHERE user_id = auth.uid()
      GROUP BY sub_category_id
      ORDER BY COUNT(*) DESC
      LIMIT 3
    )
  ORDER BY
    favorites_count DESC,  -- 熱門優先
    distance_km ASC        -- 距離近優先
  LIMIT p_limit;
END;
$$;
```

---

## 總結

### 架構設計原則

1. **職責分離**：Edge Function 處理簡單邏輯和外部整合，RPC 處理複雜的資料庫查詢
2. **性能優先**：使用 PostGIS 索引和子查詢優化，確保毫秒級查詢
3. **安全第一**：JWT 驗證、RLS 策略、SECURITY DEFINER 多重保障
4. **易於維護**：清晰的程式碼結構、完整的註解、詳細的文件

### 為什麼這個架構是最佳實踐

✅ **Edge Function (save-location)** 負責簡單的地點儲存
  - 靈活：未來可整合 Google Maps API
  - 易除錯：TypeScript + console.log
  - 易擴展：可加入反向地理編碼等功能

✅ **RPC (search_items)** 負責複雜的距離計算
  - 高效：PostGIS 空間查詢 + 索引優化
  - 安全：自動取得使用者位置，無法偽造
  - 強大：支援多種篩選和排序條件

✅ **職責清楚、性能優異、安全可靠**

---

## 相關文件

- [快速開始指南](../frontend/QUICK_START.md)
- [前端整合指南](../frontend/INTEGRATION_GUIDE.md)
- [Staging 部署指南](STAGING_DEPLOYMENT.md)
- [Supabase Edge Functions 官方文檔](https://supabase.com/docs/guides/functions)
- [PostGIS 官方文檔](https://postgis.net/documentation/)

---

**最後更新**：2025-10-30
**版本**：1.0.0
