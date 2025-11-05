# Save Location Edge Function

## 📝 功能概述

此 Edge Function 負責處理用戶地理位置的儲存，包含：

1. **接收經緯度座標**：從前端接收 GPS 座標
2. **地址解析**：呼叫 Google Maps Geocoding API 並**直接提取行政區**
3. **資料驗證**：驗證座標格式、地點類型、主要地點邏輯
4. **資料庫儲存**：將行政區儲存到 `formatted_address` 欄位，經緯度以 POINT 格式儲存到 `coordinates` 欄位

---

## 🎯 核心特性

### 1. 行政區提取

**不儲存完整地址，只儲存行政區**

```
輸入座標: (24.1817, 120.7344)
↓
Google Maps API 回應:
  formatted_address: "408台中市南屯區文心路一段186號"
  address_components: [
    { long_name: "台中市", types: ["administrative_area_level_1"] },
    { long_name: "南屯區", types: ["administrative_area_level_3"] }
  ]
↓
提取結果: "台中市南屯區"
↓
儲存到 formatted_address 欄位
```

**行政區提取邏輯**：
- 優先提取：`administrative_area_level_1`（縣市）+ `administrative_area_level_3`（區）
- 備援提取：`administrative_area_level_1` + `locality`
- 如果只有縣市：返回縣市名稱
- 如果完全無法提取：使用完整地址作為備援

### 2. 座標儲存格式

使用 **WKT (Well-Known Text)** 格式儲存 POINT：

```typescript
const wktPoint = `POINT(${longitude} ${latitude})`
// 例如: "POINT(120.7344 24.1817)"
```

**注意**：POINT 格式為 `POINT(經度 緯度)`，與通常的 `(緯度, 經度)` 順序不同。

### 3. 地點類型驗證

```typescript
const validTypes = ['家', '公司', '其他']
```

- ✅ 允許的值：`'家'`, `'公司'`, `'其他'`
- ⚠️ 未提供時：自動設定為 `'其他'`
- ❌ 無效值：返回 400 錯誤並列出有效選項

### 4. 主要地點邏輯

**智慧型 `is_primary` 設定**：

```typescript
// 情況 A: 前端明確指定 (true/false)
if (typeof is_primary === 'boolean') {
  // 使用前端指定的值
}

// 情況 B: 前端未指定 (undefined)
else {
  // 檢查用戶是否已有地點
  if (用戶沒有任何地點) {
    is_primary = true  // 第一個地點，設為主要
  } else {
    is_primary = false // 已有地點，設為非主要
  }
}
```

**主要地點更新邏輯**：

```typescript
if (is_primary === true) {
  // 將同類型的其他主要地點設為非主要
  UPDATE locations 
  SET is_primary = false 
  WHERE user_id = ? AND type = ? AND is_primary = true
}
```

**範例場景**：

| 用戶現有地點 | 新增請求 | 結果 |
|------------|---------|------|
| 無 | `{ type: '家', is_primary: undefined }` | ✅ 自動設為 `is_primary = true` |
| 家 (主要) | `{ type: '公司', is_primary: true }` | ✅ 家保持主要，公司設為主要 |
| 家 (主要) | `{ type: '家', is_primary: true }` | ✅ 舊的家設為非主要，新的家設為主要 |
| 家 (主要) | `{ type: '其他', is_primary: false }` | ✅ 家保持主要，其他設為非主要 |

---

## 📥 API 規格

### 請求格式

```http
POST /functions/v1/save-location
Authorization: Bearer {USER_JWT_TOKEN}
Content-Type: application/json

{
  "latitude": 24.1817,
  "longitude": 120.7344,
  "type": "家",           // 可選，預設 "其他"
  "is_primary": true     // 可選，自動判斷
}
```

### 成功回應 (200 OK)

```json
{
  "success": true,
  "data": {
    "id": 123,
    "latitude": 24.1817,
    "longitude": 120.7344,
    "district": "台中市南屯區",
    "type": "家",
    "is_primary": true
  },
  "message": "地點儲存成功"
}
```

### 錯誤回應

#### 401 Unauthorized - 未認證

```json
{
  "error": "Missing authorization header"
}
```

#### 400 Bad Request - 無效座標

```json
{
  "error": "無效的座標格式：緯度需在 -90 到 90 之間，經度需在 -180 到 180 之間"
}
```

#### 400 Bad Request - 無效類型

```json
{
  "error": "無效的地點類型",
  "valid_types": ["家", "公司", "其他"],
  "received": "辦公室"
}
```

#### 500 Internal Server Error - Geocoding 失敗

```json
{
  "error": "地址解析失敗",
  "details": "Geocoding failed: ZERO_RESULTS"
}
```

#### 500 Internal Server Error - 資料庫錯誤

```json
{
  "error": "儲存地點失敗",
  "details": "duplicate key value violates unique constraint"
}
```

---

## 🗂️ 檔案結構

```
save-location/
├── index.ts         # Edge Function 主程式
├── geocoding.ts     # Google Maps API 包裝函數
├── types.ts         # TypeScript 型別定義
└── README.md        # 本文件
```

### `index.ts`
- 處理 HTTP 請求/回應
- 用戶身份驗證
- 請求參數驗證
- 呼叫 geocoding 函數
- 資料庫操作
- 錯誤處理

### `geocoding.ts`
- `getAddressFromCoordinates()`: 呼叫 Google Maps API 並提取行政區
- `extractDistrict()`: 從 address_components 提取縣市和區域

### `types.ts`
- TypeScript 介面定義
- 請求/回應型別

---

## 🔧 環境變數

### 必需變數

```bash
GOOGLE_MAPS_API_KEY=your_google_maps_api_key
```

### Supabase 自動提供

```bash
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGc...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGc...
```

### 本地開發設定

建立 `backend/supabase/.env` 檔案：

```bash
GOOGLE_MAPS_API_KEY=AIzaSyC...your_key_here
```

---

## 🚀 部署指令

### 部署到 Supabase

```bash
# 1. 登入
npx supabase login

# 2. 連結專案
npx supabase link --project-ref your-project-ref

# 3. 部署函數
npx supabase functions deploy save-location

# 4. 設定環境變數
npx supabase secrets set GOOGLE_MAPS_API_KEY=your_api_key_here
```

### 本地測試

```bash
# 啟動本地開發環境
npx supabase functions serve save-location --env-file ./supabase/.env

# 測試請求
curl -i --location --request POST \
  'http://localhost:54321/functions/v1/save-location' \
  --header 'Authorization: Bearer eyJhbGc...' \
  --header 'Content-Type: application/json' \
  --data '{
    "latitude": 24.1817,
    "longitude": 120.7344,
    "type": "家",
    "is_primary": true
  }'
```

---

## 📊 資料庫 Schema

### `locations` 表

```sql
CREATE TABLE public.locations (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL,
  coordinates GEOGRAPHY(Point, 4326) NOT NULL,  -- POINT(經度 緯度)
  type VARCHAR(50) CHECK (type IN ('家', '公司', '其他')),
  is_primary BOOLEAN NOT NULL DEFAULT false,
  formatted_address TEXT,                       -- 儲存行政區
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);
```

### 資料範例

```sql
INSERT INTO locations (user_id, coordinates, type, is_primary, formatted_address)
VALUES (
  'user-uuid-here',
  'POINT(120.7344 24.1817)',
  '家',
  true,
  '台中市南屯區'
);
```

### 查詢範例

```sql
-- 查詢用戶的所有地點
SELECT 
  id,
  ST_Y(coordinates::geometry) as latitude,
  ST_X(coordinates::geometry) as longitude,
  formatted_address as district,
  type,
  is_primary
FROM locations
WHERE user_id = 'user-uuid-here';

-- 查詢主要地點
SELECT * FROM locations 
WHERE user_id = 'user-uuid-here' AND is_primary = true;

-- 查詢特定類型的主要地點
SELECT * FROM locations 
WHERE user_id = 'user-uuid-here' AND type = '家' AND is_primary = true;
```

---

## 🧪 測試案例

### 測試 1: 基本功能測試

```bash
curl -X POST http://localhost:54321/functions/v1/save-location \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "latitude": 24.1817,
    "longitude": 120.7344,
    "type": "家",
    "is_primary": true
  }'
```

**預期結果**：
- ✅ 200 OK
- ✅ `district` 為 "台中市南屯區" 或類似行政區
- ✅ 資料庫插入成功

### 測試 2: 自動設定 is_primary

```bash
# 第一個地點（未指定 is_primary）
curl -X POST http://localhost:54321/functions/v1/save-location \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "latitude": 24.1817,
    "longitude": 120.7344,
    "type": "家"
  }'
```

**預期結果**：
- ✅ `is_primary` 自動設為 `true`（因為是第一個地點）

### 測試 3: 主要地點更新邏輯

```bash
# 1. 新增第一個「家」地點
curl -X POST ... -d '{"latitude": 24.1817, "longitude": 120.7344, "type": "家", "is_primary": true}'

# 2. 新增第二個「家」地點（設為主要）
curl -X POST ... -d '{"latitude": 24.2000, "longitude": 120.8000, "type": "家", "is_primary": true}'
```

**預期結果**：
- ✅ 第一個「家」的 `is_primary` 變為 `false`
- ✅ 第二個「家」的 `is_primary` 為 `true`

### 測試 4: 無效座標

```bash
curl -X POST ... -d '{"latitude": 999, "longitude": 120.7344}'
```

**預期結果**：
- ❌ 400 Bad Request
- 錯誤訊息包含 "無效的座標格式"

### 測試 5: 無效類型

```bash
curl -X POST ... -d '{"latitude": 24.1817, "longitude": 120.7344, "type": "學校"}'
```

**預期結果**：
- ❌ 400 Bad Request
- 錯誤訊息包含 `valid_types: ["家", "公司", "其他"]`

---

## 🔍 日誌範例

### 成功案例

```
📍 處理用戶 abc-123-def 的地理位置: 24.1817, 120.7344
   類型: 家, 主要地點: true
🌍 Calling Google Maps API: 24.1817, 120.7344
✅ 提取行政區: 台中市南屯區
✅ 行政區解析成功: 台中市南屯區
✅ 已將其他「家」類型的主要地點設為非主要
💾 儲存地點到資料庫: coordinates=POINT(120.7344 24.1817), formatted_address=台中市南屯區
✅ 地點儲存成功，ID: 123
```

### 自動設定 is_primary 的案例

```
📍 處理用戶 abc-123-def 的地理位置: 24.1817, 120.7344
   類型: 其他, 主要地點: false
⚠️ 未指定地點類型，預設為「其他」
ℹ️ 自動設定 is_primary: true (用戶首次地點)
```

### 錯誤案例

```
❌ Geocoding 失敗: Error: Geocoding failed: ZERO_RESULTS
```

---

## ⚠️ 注意事項

### 1. POINT 格式順序

```
正確: POINT(經度 緯度)
正確: POINT(120.7344 24.1817)
錯誤: POINT(24.1817 120.7344)  ❌
```

### 2. 行政區提取限制

- 只支援台灣地址格式
- 海外座標可能只返回國家名稱
- 偏遠地區可能只返回縣市

### 3. Google Maps API 配額

- 免費額度: 每月 $200 USD
- Geocoding API: 每 1000 次請求 $5 USD
- 建議實作快取機制減少 API 呼叫

### 4. 主要地點邏輯

- 每個類型可以有多個地點
- 每個類型只能有一個主要地點
- 不同類型的主要地點互不影響

---

## 📚 相關文件

- [Supabase Edge Functions 文件](https://supabase.com/docs/guides/functions)
- [Google Maps Geocoding API](https://developers.google.com/maps/documentation/geocoding)
- [PostgreSQL Geography 型別](https://postgis.net/docs/using_postgis_dbmanagement.html#Geography_Basics)
- [Well-Known Text (WKT) 格式](https://en.wikipedia.org/wiki/Well-known_text_representation_of_geometry)

---

**版本**: 2.0.0  
**最後更新**: 2025-11-05  
**維護者**: FCU-Sigma Backend Team
