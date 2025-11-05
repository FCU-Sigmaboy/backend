# 後端地址解析方案（Supabase Edge Function）

**需求變更**: 前端只負責取得座標，地址解析由 Supabase 服務實作  
**日期**: 2025-11-05  
**優點**: API Key 安全性更高、邏輯集中在後端

---

## 🎯 新架構設計

### 職責分離

```
┌─────────────────────────────────────────────────────────────────┐
│                          職責劃分                                │
└─────────────────────────────────────────────────────────────────┘

前端職責：
  • 取得瀏覽器地理位置（經緯度）
  • 呼叫後端 Edge Function
  • 顯示結果和錯誤訊息

後端職責（Supabase Edge Function）：
  • 接收座標
  • 呼叫 Google Maps Geocoding API
  • 解析地址
  • 儲存到資料庫
  • 返回結果
```

### 優點分析

| 項目 | 前端解析（舊方案） | 後端解析（新方案） |
|------|-------------------|-------------------|
| **API Key 安全** | ❌ 暴露在前端 | ✅ 儲存在後端環境變數 |
| **網域限制** | ⚠️ 可能被繞過 | ✅ 完全控制 |
| **配額管理** | ❌ 難以監控 | ✅ 集中管理 |
| **錯誤處理** | ⚠️ 前端處理 | ✅ 後端統一處理 |
| **資料一致性** | ⚠️ 分離的操作 | ✅ 原子操作 |
| **快取管理** | ❌ 難以實作 | ✅ 後端快取 |
| **審計日誌** | ❌ 無 | ✅ 完整記錄 |

---

## 💻 實作方案

### 架構圖

```
前端                    Supabase                 Google Maps        資料庫
 |                          |                         |               |
 |-- 取得座標 ------------>|                         |               |
 |    {lat, lng}            |                         |               |
 |                          |                         |               |
 |-- POST /save-location -->|                         |               |
 |                          |                         |               |
 |                          |-- 檢查用戶權限          |               |
 |                          |                         |               |
 |                          |-- 呼叫 Geocoding API -->|               |
 |                          |<-- formatted_address ---|               |
 |                          |                         |               |
 |                          |-- 儲存到 locations ---->|               |
 |                          |<-- success -------------|               |
 |                          |                         |               |
 |<-- 返回結果 -------------|                         |               |
```

---

## 📁 檔案結構

```
project/
├── backend/
│   └── supabase/
│       └── functions/
│           └── save-location/
│               ├── index.ts          # Edge Function 主檔案
│               ├── geocoding.ts      # Google Maps API 包裝
│               └── types.ts          # TypeScript 型別定義
│
└── frontend-demo/
    └── src/
        └── api/
            └── locationAPI.js        # 前端 API（簡化版）
```

---

## 🔧 實作細節

### 1. Supabase Edge Function

#### 檔案：`backend/supabase/functions/save-location/index.ts`

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { getAddressFromCoordinates } from './geocoding.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface SaveLocationRequest {
  latitude: number
  longitude: number
  type?: string
  is_primary?: boolean
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. 驗證請求方法
    if (req.method !== 'POST') {
      throw new Error('Method not allowed')
    }

    // 2. 取得認證 token
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 3. 建立 Supabase 客戶端
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    )

    // 4. 驗證用戶身份
    const {
      data: { user },
      error: userError,
    } = await supabaseClient.auth.getUser()

    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 5. 解析請求 body
    const body: SaveLocationRequest = await req.json()
    const { latitude, longitude, type = '其他', is_primary = true } = body

    // 6. 驗證座標格式
    if (
      typeof latitude !== 'number' ||
      typeof longitude !== 'number' ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      return new Response(
        JSON.stringify({ error: 'Invalid coordinates' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 7. 驗證地點類型
    const validTypes = ['家', '公司', '其他']
    if (!validTypes.includes(type)) {
      return new Response(
        JSON.stringify({ error: 'Invalid location type' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`📍 Processing location for user ${user.id}: ${latitude}, ${longitude}`)

    // 8. 呼叫 Google Maps Geocoding API
    let formattedAddress: string
    try {
      formattedAddress = await getAddressFromCoordinates(latitude, longitude)
      console.log(`✅ Address resolved: ${formattedAddress}`)
    } catch (error) {
      console.error('❌ Geocoding failed:', error)
      return new Response(
        JSON.stringify({ 
          error: 'Failed to resolve address',
          details: error.message 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 9. 如果設為主要地點，先將其他地點設為非主要
    if (is_primary) {
      const { error: updateError } = await supabaseClient
        .from('locations')
        .update({ is_primary: false })
        .eq('user_id', user.id)

      if (updateError) {
        console.warn('Failed to update other locations:', updateError)
      }
    }

    // 10. 儲存到資料庫（使用 Service Role Key 繞過 RLS）
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // 構建 WKT 格式的座標
    const wktPoint = `POINT(${longitude} ${latitude})`

    const { data, error: insertError } = await supabaseAdmin
      .from('locations')
      .insert({
        user_id: user.id,
        coordinates: wktPoint,
        type: type,
        is_primary: is_primary,
        formatted_address: formattedAddress,
      })
      .select()
      .single()

    if (insertError) {
      console.error('❌ Database insert failed:', insertError)
      return new Response(
        JSON.stringify({ 
          error: 'Failed to save location',
          details: insertError.message 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('✅ Location saved successfully')

    // 11. 返回成功結果
    return new Response(
      JSON.stringify({
        success: true,
        data: {
          id: data.id,
          latitude,
          longitude,
          address: formattedAddress,
          type,
          is_primary,
        },
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('❌ Unexpected error:', error)
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error',
        details: error.message 
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
```

---

#### 檔案：`backend/supabase/functions/save-location/geocoding.ts`

```typescript
const GOOGLE_MAPS_API_KEY = Deno.env.get('GOOGLE_MAPS_API_KEY')

interface GeocodingResponse {
  results: Array<{
    formatted_address: string
    geometry: {
      location: {
        lat: number
        lng: number
      }
    }
    address_components: Array<{
      long_name: string
      short_name: string
      types: string[]
    }>
  }>
  status: string
  error_message?: string
}

/**
 * 使用 Google Maps Geocoding API 取得地址
 */
export async function getAddressFromCoordinates(
  latitude: number,
  longitude: number
): Promise<string> {
  if (!GOOGLE_MAPS_API_KEY) {
    throw new Error('Google Maps API key is not configured')
  }

  const url = new URL('https://maps.googleapis.com/maps/api/geocode/json')
  url.searchParams.append('latlng', `${latitude},${longitude}`)
  url.searchParams.append('key', GOOGLE_MAPS_API_KEY)
  url.searchParams.append('language', 'zh-TW')
  url.searchParams.append('region', 'TW')

  console.log(`🌍 Calling Google Maps API: ${latitude}, ${longitude}`)

  const response = await fetch(url.toString(), {
    method: 'GET',
    headers: {
      'Accept': 'application/json',
    },
  })

  if (!response.ok) {
    throw new Error(`Google Maps API returned ${response.status}`)
  }

  const data: GeocodingResponse = await response.json()

  if (data.status !== 'OK') {
    console.error('Google Maps API error:', data)
    throw new Error(`Geocoding failed: ${data.status} - ${data.error_message || 'Unknown error'}`)
  }

  if (!data.results || data.results.length === 0) {
    throw new Error('No address found for the given coordinates')
  }

  // 取得第一個結果的格式化地址
  const formattedAddress = data.results[0].formatted_address

  return formattedAddress
}

/**
 * 【可選】提取行政區資訊
 * 從地址組件中提取縣市和區域
 */
export function extractDistrict(addressComponents: GeocodingResponse['results'][0]['address_components']): string | null {
  let city = ''
  let district = ''

  for (const component of addressComponents) {
    // 尋找縣市
    if (component.types.includes('administrative_area_level_1')) {
      city = component.long_name
    }
    // 尋找區域
    if (component.types.includes('administrative_area_level_3')) {
      district = component.long_name
    }
  }

  if (city && district) {
    return `${city}${district}`
  }

  return null
}
```

---

#### 檔案：`backend/supabase/functions/save-location/types.ts`

```typescript
export interface SaveLocationRequest {
  latitude: number
  longitude: number
  type?: string
  is_primary?: boolean
}

export interface SaveLocationResponse {
  success: boolean
  data?: {
    id: number
    latitude: number
    longitude: number
    address: string
    type: string
    is_primary: boolean
  }
  error?: string
  details?: string
}
```

---

### 2. 前端實作（簡化版）

#### 檔案：`frontend-demo/src/api/locationAPI.js`

```javascript
import { supabase } from '@/lib/supabase'

/**
 * 【功能】取得瀏覽器地理位置
 * @returns {Promise<{latitude: number, longitude: number}>}
 */
export async function getBrowserLocation() {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error('您的瀏覽器不支援地理定位功能'))
      return
    }

    console.log('📍 正在取得地理位置...')

    navigator.geolocation.getCurrentPosition(
      (position) => {
        const { latitude, longitude } = position.coords
        console.log('✅ 地理位置取得成功:', { latitude, longitude })
        resolve({ latitude, longitude })
      },
      (error) => {
        console.error('❌ 地理位置取得失敗:', error)
        
        let errorMessage = '無法取得您的位置'
        switch (error.code) {
          case error.PERMISSION_DENIED:
            errorMessage = '您拒絕了地理位置權限，請在瀏覽器設定中允許'
            break
          case error.POSITION_UNAVAILABLE:
            errorMessage = '位置資訊無法取得'
            break
          case error.TIMEOUT:
            errorMessage = '取得位置超時，請重試'
            break
        }
        
        reject(new Error(errorMessage))
      },
      {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 0
      }
    )
  })
}

/**
 * 【功能】呼叫後端儲存地理位置（包含地址解析）
 * @param {number} latitude - 緯度
 * @param {number} longitude - 經度
 * @param {string} type - 地點類型
 * @param {boolean} isPrimary - 是否為主要地點
 * @returns {Promise<object>}
 */
export async function saveLocationToBackend(
  latitude,
  longitude,
  type = '其他',
  isPrimary = true
) {
  try {
    console.log('💾 呼叫後端儲存地理位置...')

    // 取得認證 token
    const { data: { session }, error: sessionError } = await supabase.auth.getSession()
    
    if (sessionError || !session) {
      throw new Error('請先登入')
    }

    // 呼叫 Edge Function
    const { data, error } = await supabase.functions.invoke('save-location', {
      body: {
        latitude,
        longitude,
        type,
        is_primary: isPrimary,
      },
    })

    if (error) {
      console.error('❌ Edge Function 錯誤:', error)
      throw new Error(error.message || '儲存失敗')
    }

    if (!data.success) {
      throw new Error(data.error || '儲存失敗')
    }

    console.log('✅ 地理位置儲存成功:', data)
    return {
      success: true,
      location: data.data,
    }

  } catch (error) {
    console.error('❌ 儲存地理位置失敗:', error)
    return {
      success: false,
      error: error.message,
    }
  }
}

/**
 * 【整合函數】完整的地理位置處理流程
 * 1. 取得瀏覽器位置
 * 2. 呼叫後端 Edge Function（自動處理地址解析和儲存）
 */
export async function handleLocationFlow(type = '其他', isPrimary = true) {
  try {
    // 步驟 1: 取得座標
    const { latitude, longitude } = await getBrowserLocation()

    // 步驟 2: 呼叫後端處理（包含地址解析和儲存）
    const result = await saveLocationToBackend(latitude, longitude, type, isPrimary)

    if (result.success) {
      return {
        success: true,
        location: result.location,
      }
    } else {
      return {
        success: false,
        error: result.error,
      }
    }

  } catch (error) {
    return {
      success: false,
      error: error.message,
    }
  }
}

/**
 * 【輔助函數】檢查用戶是否已有地理位置
 */
export async function hasUserLocation() {
  try {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return false

    const { data, error } = await supabase
      .from('locations')
      .select('id')
      .eq('user_id', user.id)
      .limit(1)
      .single()

    return !!data && !error

  } catch (error) {
    return false
  }
}
```

---

### 3. 環境變數設定

#### Supabase 專案設定

在 Supabase Dashboard → Settings → Edge Functions → Secrets 中設定：

```bash
# Google Maps API Key（後端專用）
GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here

# Supabase（自動提供，無需手動設定）
SUPABASE_URL=auto_provided
SUPABASE_ANON_KEY=auto_provided
SUPABASE_SERVICE_ROLE_KEY=auto_provided
```

#### 本地開發環境

**檔案**: `backend/supabase/.env`

```bash
# Google Maps API Key
GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here
```

---

### 4. 部署 Edge Function

#### 使用 Supabase CLI

```bash
# 1. 登入 Supabase
npx supabase login

# 2. 連結到專案
npx supabase link --project-ref your-project-ref

# 3. 部署 Edge Function
npx supabase functions deploy save-location

# 4. 設定環境變數（secrets）
npx supabase secrets set GOOGLE_MAPS_API_KEY=your_api_key_here
```

#### 驗證部署

```bash
# 測試 Edge Function
curl -i --location --request POST \
  'https://your-project-ref.supabase.co/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_ANON_KEY' \
  --header 'Content-Type: application/json' \
  --data '{"latitude":24.1817,"longitude":120.7344,"type":"其他","is_primary":true}'
```

---

## 🔄 完整流程對比

### 新方案（後端解析）

```
前端                          Edge Function              Google Maps        資料庫
 |                                  |                          |               |
 |-- getBrowserLocation() -------->|                          |               |
 |<-- {lat, lng} -------------------|                          |               |
 |                                  |                          |               |
 |-- saveLocationToBackend() ------>|                          |               |
 |    {lat, lng, type}              |                          |               |
 |                                  |                          |               |
 |                                  |-- 驗證用戶權限           |               |
 |                                  |                          |               |
 |                                  |-- getAddressFromCoordinates() --------->|
 |                                  |<-- formatted_address ----|               |
 |                                  |                          |               |
 |                                  |-- 更新 is_primary ---------------------->|
 |                                  |                          |               |
 |                                  |-- 插入 location ------------------------>|
 |                                  |<-- success ----------------------------|
 |                                  |                          |               |
 |<-- {success, location} ----------|                          |               |
 |                                  |                          |               |
```

### 舊方案（前端解析）

```
前端                          Google Maps              資料庫
 |                                  |                       |
 |-- getBrowserLocation() -------->|                       |
 |<-- {lat, lng} -------------------|                       |
 |                                  |                       |
 |-- getAddressFromCoordinates() -->|                       |
 |<-- formatted_address ------------|                       |
 |                                  |                       |
 |-- saveLocation() ----------------------------------->|
 |<-- success ------------------------------------------|
 |                                  |                       |
```

---

## ✅ 優勢總結

### 安全性

| 項目 | 舊方案 | 新方案 |
|------|--------|--------|
| API Key 暴露 | ❌ 前端可見 | ✅ 後端環境變數 |
| 請求來源驗證 | ⚠️ HTTP Referrer | ✅ Service 端驗證 |
| 用戶身份驗證 | ⚠️ 前端處理 | ✅ Edge Function 驗證 |
| 配額濫用風險 | ❌ 高 | ✅ 低 |

### 維護性

| 項目 | 舊方案 | 新方案 |
|------|--------|--------|
| API 變更 | ❌ 需更新前端 | ✅ 只改後端 |
| 錯誤處理 | ⚠️ 分散 | ✅ 集中 |
| 日誌記錄 | ❌ 難以追蹤 | ✅ 完整日誌 |
| 測試 | ⚠️ 複雜 | ✅ 易於測試 |

### 功能性

| 項目 | 舊方案 | 新方案 |
|------|--------|--------|
| 快取 | ❌ 無 | ✅ 可實作 |
| 批次處理 | ❌ 難 | ✅ 易 |
| 審計日誌 | ❌ 無 | ✅ 完整 |
| 速率限制 | ❌ 無 | ✅ 可控制 |

---

## 🧪 測試方案

### 1. 本地測試 Edge Function

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
    "type": "其他",
    "is_primary": true
  }'
```

### 2. 前端整合測試

```javascript
// 測試完整流程
async function testLocationFlow() {
  try {
    const result = await handleLocationFlow('其他', true)
    
    if (result.success) {
      console.log('✅ 測試成功!')
      console.log('地址:', result.location.address)
      console.log('座標:', result.location.latitude, result.location.longitude)
    } else {
      console.error('❌ 測試失敗:', result.error)
    }
  } catch (error) {
    console.error('❌ 測試錯誤:', error)
  }
}
```

### 3. 單元測試 Geocoding 函數

**檔案**: `backend/supabase/functions/save-location/geocoding.test.ts`

```typescript
import { assertEquals } from 'https://deno.land/std@0.168.0/testing/asserts.ts'
import { getAddressFromCoordinates } from './geocoding.ts'

Deno.test('getAddressFromCoordinates - 台中市座標', async () => {
  const address = await getAddressFromCoordinates(24.1817, 120.7344)
  
  // 驗證地址包含台中市
  assertEquals(address.includes('台中市'), true)
})

Deno.test('getAddressFromCoordinates - 無效座標', async () => {
  try {
    await getAddressFromCoordinates(999, 999)
    // 應該拋出錯誤
    assertEquals(true, false)
  } catch (error) {
    assertEquals(error instanceof Error, true)
  }
})
```

---

## 📊 效能考量

### 快取策略（可選實作）

```typescript
// 在 geocoding.ts 中添加快取
const geocodingCache = new Map<string, { address: string, timestamp: number }>()
const CACHE_TTL = 24 * 60 * 60 * 1000 // 24 小時

export async function getAddressFromCoordinates(
  latitude: number,
  longitude: number
): Promise<string> {
  // 建立快取 key（精確到小數點後 4 位，約 11 公尺）
  const cacheKey = `${latitude.toFixed(4)},${longitude.toFixed(4)}`
  
  // 檢查快取
  const cached = geocodingCache.get(cacheKey)
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    console.log('✅ 使用快取的地址')
    return cached.address
  }
  
  // 呼叫 API
  const address = await callGoogleMapsAPI(latitude, longitude)
  
  // 儲存到快取
  geocodingCache.set(cacheKey, { address, timestamp: Date.now() })
  
  return address
}
```

---

## 🚨 注意事項

### 成本控制

1. **Google Maps API 配額**
   - 免費額度: 每月 $200 USD
   - Geocoding API: 每 1000 次請求 $5 USD
   - 建議設定每日配額上限

2. **Supabase Edge Function**
   - 免費方案: 每月 500,000 次請求
   - 每次請求計時: 50KB 輸入/輸出

### 錯誤處理

1. **Google Maps API 失敗**
   - 記錄錯誤但不阻斷用戶
   - 儲存座標但地址為空
   - 可以稍後重試解析

2. **網路超時**
   - 設定合理的超時時間（5-10 秒）
   - 提供重試機制

---

## 📚 相關文件

- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Deno Deploy](https://deno.com/deploy/docs)
- [Google Maps Geocoding API](https://developers.google.com/maps/documentation/geocoding)

---

**撰寫日期**: 2025-11-05  
**版本**: 2.0.0  
**架構**: 後端地址解析（推薦）
