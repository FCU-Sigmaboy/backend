# save-location Edge Function

## 功能概述

這個 Edge Function 提供兩個主要功能：

1. **GET 請求**：獲取使用者已儲存的主要位置
2. **POST 請求**：儲存或更新使用者的地理位置

## 核心邏輯

### 首次使用流程
```
使用者註冊 → 登入 → GET 請求（返回無位置）
    ↓
使用者點擊「獲取位置」按鈕
    ↓
POST 請求 → 檢查是否已有位置 → 沒有 → INSERT 新記錄
    ↓
位置已儲存（is_primary = true）
```

### 後續登入流程
```
使用者登入 → GET 請求 → 返回已儲存的位置
    ↓
前端自動在地圖上顯示該位置（不需要使用者點擊按鈕）
    ↓
（如果使用者想更新位置）
    ↓
POST 請求 → 檢查是否已有位置 → 有 → UPDATE 現有記錄
```

## API 規格

### 端點
```
GET/POST /functions/v1/save-location
```

### 認證
所有請求都需要 JWT Token：
```
Authorization: Bearer <user_jwt_token>
```

---

## GET 請求：獲取已儲存的位置

### 請求
```bash
curl -X GET 'http://localhost:54321/functions/v1/save-location' \
  -H 'Authorization: Bearer YOUR_JWT_TOKEN'
```

### 回應

#### 情況 1：使用者已有儲存的位置
```json
{
  "success": true,
  "hasLocation": true,
  "data": {
    "id": 1,
    "coordinates": {
      "latitude": 25.0330,
      "longitude": 121.5654
    },
    "type": "其他",
    "is_primary": true,
    "formatted_address": "台北市信義區信義路五段7號",
    "created_at": "2025-10-31T10:30:00Z",
    "updated_at": "2025-10-31T10:30:00Z"
  }
}
```

#### 情況 2：使用者尚未儲存位置
```json
{
  "success": true,
  "hasLocation": false,
  "data": null
}
```

### 錯誤回應
```json
{
  "success": false,
  "error": "Missing Authorization header"
}
```

---

## POST 請求：儲存或更新位置

### 請求參數

| 參數 | 類型 | 必填 | 預設值 | 說明 |
|------|------|------|--------|------|
| `latitude` | number | ✅ | - | 緯度（-90 ~ 90） |
| `longitude` | number | ✅ | - | 經度（-180 ~ 180） |
| `type` | string | ❌ | '其他' | 地點類型：'家'、'公司'、'其他' |
| `is_primary` | boolean | ❌ | true | 是否為主要地點 |
| `formatted_address` | string | ❌ | null | 格式化地址 |

### 請求範例

#### 首次儲存位置
```bash
curl -X POST 'http://localhost:54321/functions/v1/save-location' \
  -H 'Authorization: Bearer YOUR_JWT_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{
    "latitude": 25.0330,
    "longitude": 121.5654,
    "type": "家",
    "is_primary": true,
    "formatted_address": "台北市信義區信義路五段7號"
  }'
```

#### 更新位置
```bash
curl -X POST 'http://localhost:54321/functions/v1/save-location' \
  -H 'Authorization: Bearer YOUR_JWT_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{
    "latitude": 25.0400,
    "longitude": 121.5700,
    "formatted_address": "台北市信義區市府路1號"
  }'
```

### 回應

#### 首次儲存（INSERT）
```json
{
  "success": true,
  "message": "Location saved successfully",
  "isNewLocation": true,
  "data": {
    "id": 1,
    "coordinates": {
      "latitude": 25.0330,
      "longitude": 121.5654
    },
    "type": "家",
    "is_primary": true,
    "formatted_address": "台北市信義區信義路五段7號",
    "created_at": "2025-10-31T10:30:00Z",
    "updated_at": "2025-10-31T10:30:00Z"
  }
}
```

#### 更新位置（UPDATE）
```json
{
  "success": true,
  "message": "Location updated successfully",
  "isNewLocation": false,
  "data": {
    "id": 1,
    "coordinates": {
      "latitude": 25.0400,
      "longitude": 121.5700
    },
    "type": "其他",
    "is_primary": true,
    "formatted_address": "台北市信義區市府路1號",
    "created_at": "2025-10-31T10:30:00Z",
    "updated_at": "2025-10-31T11:00:00Z"
  }
}
```

### 錯誤回應

#### 驗證錯誤
```json
{
  "success": false,
  "error": "Invalid coordinates: latitude and longitude must be numbers"
}
```

#### 認證錯誤
```json
{
  "success": false,
  "error": "Unauthorized: Invalid or expired token"
}
```

---

## 前端整合指南

### Vue 3 範例

#### 1. 登入時自動載入位置

```javascript
import { ref, onMounted } from 'vue'
import { supabase } from './supabase.js'

const userLocation = ref(null)

onMounted(async () => {
  // 檢查使用者是否已登入
  const { data: { session } } = await supabase.auth.getSession()

  if (session) {
    // 使用者已登入，獲取已儲存的位置
    const { data, error } = await supabase.functions.invoke('save-location', {
      method: 'GET'
    })

    if (data?.hasLocation) {
      userLocation.value = data.data.coordinates
      // 在地圖上顯示位置
      showLocationOnMap(userLocation.value)
    } else {
      // 使用者尚未設定位置，顯示預設位置或提示使用者設定
      console.log('使用者尚未設定位置')
    }
  }
})
```

#### 2. 儲存或更新位置

```javascript
const saveLocation = async (latitude, longitude, formattedAddress) => {
  try {
    const { data, error } = await supabase.functions.invoke('save-location', {
      method: 'POST',
      body: {
        latitude,
        longitude,
        formatted_address: formattedAddress
      }
    })

    if (error) throw error

    if (data.isNewLocation) {
      console.log('位置已儲存！')
    } else {
      console.log('位置已更新！')
    }

    return data
  } catch (error) {
    console.error('儲存位置失敗:', error)
    throw error
  }
}
```

---

## 資料庫結構

### locations 表

| 欄位 | 類型 | 說明 |
|------|------|------|
| `id` | BIGSERIAL | 主鍵 |
| `user_id` | UUID | 使用者 ID（外鍵到 auth.users） |
| `coordinates` | GEOGRAPHY(Point, 4326) | PostGIS 地理點 |
| `type` | VARCHAR(50) | 地點類型 |
| `is_primary` | BOOLEAN | 是否為主要地點 |
| `formatted_address` | TEXT | 格式化地址 |
| `created_at` | TIMESTAMPTZ | 建立時間 |
| `updated_at` | TIMESTAMPTZ | 更新時間 |

### RPC 函數

#### get_user_primary_location(p_user_id UUID)

此函數用於 GET 請求，提取使用者的主要位置並將 PostGIS POINT 格式轉換為經緯度。

```sql
SELECT * FROM get_user_primary_location('user-uuid');
```

---

## 安全性

### 1. JWT 認證
- 所有請求都必須提供有效的 JWT Token
- Token 從 `Authorization: Bearer <token>` header 中提取
- 使用 `supabaseAdmin.auth.getUser(token)` 驗證

### 2. RLS 策略
- 雖然 Edge Function 使用 Service Role Key
- 但邏輯上確保只能存取自己的資料（透過 `user_id` 過濾）

### 3. 輸入驗證
- 驗證經緯度範圍
- 驗證地點類型
- 防止 SQL Injection（使用參數化查詢）

---

## 故障排除

### 問題 1：GET 請求返回錯誤
**可能原因**：RPC 函數不存在

**解決方法**：
```bash
npx supabase db reset
```

### 問題 2：POST 請求無法更新
**可能原因**：沒有找到現有的主要位置

**檢查**：
```sql
SELECT * FROM locations WHERE user_id = 'your-user-id' AND is_primary = true;
```

### 問題 3：座標顯示錯誤
**可能原因**：經緯度順序錯誤

**注意**：PostGIS POINT 格式是 `POINT(longitude latitude)`，但 API 接收和返回的是 `{latitude, longitude}`

---

## 版本歷史

### v2.0.0 (2025-10-31)
- ✨ 新增 GET 請求支援，獲取已儲存的位置
- ✨ POST 請求邏輯改為：首次 INSERT，後續 UPDATE
- ✨ 新增 `isNewLocation` 標誌
- ✨ 新增 `get_user_primary_location` RPC 函數
- 📝 更新文檔和測試用例

### v1.0.0 (2025-10-28)
- 🎉 初始版本
- 支援 POST 請求儲存位置

---

**維護者**: FCU-Sigmaboy Team
**最後更新**: 2025-10-31
