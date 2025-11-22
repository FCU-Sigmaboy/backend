# 前端使用 save-location Edge Function 指南

本文件說明如何在前端應用中呼叫 `save-location` Edge Function 來儲存使用者的地理位置。

---

## 基本呼叫

### API 參數說明

| 參數 | 類型 | 必填 | 預設值 | 說明 |
|------|------|------|--------|------|
| `latitude` | number | ✅ | - | 緯度（-90 到 90） |
| `longitude` | number | ✅ | - | 經度（-180 到 180） |
| `type` | string | ❌ | '其他' | 地點類型：'家'、'公司'、'其他' |
| `is_primary` | boolean | ❌ | false | 是否為主要地點 |
| `formatted_address` | string | ❌ | null | 格式化地址（選填） |

### 基本呼叫方式

```javascript
import { supabase } from './supabaseClient'

const { data, error } = await supabase.functions.invoke('save-location', {
  body: {
    latitude: 25.0330,   // 必填
    longitude: 121.5654, // 必填
    type: '家',          // 選填，預設 '其他'
    is_primary: true,    // 選填，預設 false
    formatted_address: '台北市信義區信義路五段7號' // 選填
  }
})

if (error) {
  console.error('儲存失敗:', error)
} else {
  console.log('儲存成功:', data.data)
}
```

### 回傳資料格式

**成功時：**
```javascript
{
  success: true,
  message: "Location saved successfully",
  data: {
    id: 123,
    coordinates: {
      latitude: 25.0330,
      longitude: 121.5654
    },
    type: "家",
    is_primary: true,
    created_at: "2025-10-30T14:00:00.000Z"
  }
}
```

**失敗時：**
```javascript
{
  message: "Invalid latitude: must be between -90 and 90"
}
```

---

## 範例 1：使用 HTML5 Geolocation API

```javascript
// LocationSaver.js
import { supabase } from './supabaseClient'

export async function saveUserLocation(type = '其他', isPrimary = false) {
  // 檢查瀏覽器是否支援 Geolocation
  if (!navigator.geolocation) {
    throw new Error('您的瀏覽器不支援定位功能')
  }

  // 取得使用者位置
  return new Promise((resolve, reject) => {
    navigator.geolocation.getCurrentPosition(
      async (position) => {
        const { latitude, longitude } = position.coords

        try {
          // 呼叫 Edge Function
          const { data, error } = await supabase.functions.invoke('save-location', {
            body: {
              latitude,
              longitude,
              type,
              is_primary: isPrimary
            }
          })

          if (error) throw error

          resolve(data.data)
        } catch (err) {
          reject(err)
        }
      },
      (error) => {
        // Geolocation 錯誤處理
        switch (error.code) {
          case error.PERMISSION_DENIED:
            reject(new Error('使用者拒絕提供位置'))
            break
          case error.POSITION_UNAVAILABLE:
            reject(new Error('無法取得位置資訊'))
            break
          case error.TIMEOUT:
            reject(new Error('取得位置逾時'))
            break
          default:
            reject(new Error('發生未知錯誤'))
        }
      },
      {
        enableHighAccuracy: true, // 高精度模式
        timeout: 10000,           // 10 秒逾時
        maximumAge: 0             // 不使用快取
      }
    )
  })
}
```

---

## 在 Vue 元件中使用

```vue
<!-- SaveLocationButton.vue -->
<template>
  <div class="save-location">
    <button
      @click="handleSaveLocation"
      :disabled="loading"
      class="save-button"
    >
      {{ loading ? '儲存中...' : '儲存位置' }}
    </button>

    <div v-if="error" class="error-message">
      {{ error }}
    </div>

    <div v-if="successMessage" class="success-message">
      {{ successMessage }}
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { saveUserLocation } from './LocationSaver'

const loading = ref(false)
const error = ref(null)
const successMessage = ref(null)

async function handleSaveLocation() {
  error.value = null
  successMessage.value = null
  loading.value = true

  try {
    const result = await saveUserLocation('家', true)
    successMessage.value = `地點儲存成功！ID: ${result.id}`
  } catch (err) {
    error.value = err.message
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.save-button {
  padding: 12px 24px;
  background-color: #4CAF50;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 16px;
}

.save-button:hover:not(:disabled) {
  background-color: #45a049;
}

.save-button:disabled {
  background-color: #cccccc;
  cursor: not-allowed;
}

.error-message {
  margin-top: 10px;
  padding: 10px;
  background-color: #ffebee;
  color: #c62828;
  border-radius: 4px;
}

.success-message {
  margin-top: 10px;
  padding: 10px;
  background-color: #e8f5e9;
  color: #2e7d32;
  border-radius: 4px;
}
</style>
```

---

## 進階用法：整合 Google Maps Geocoding API

自動從經緯度取得地址：

```javascript
// saveLocationWithGeocode.js
import { supabase } from './supabaseClient'

export async function saveLocationWithGeocode(latitude, longitude, type, isPrimary) {
  try {
    // 1. 呼叫 Google Maps Geocoding API 取得地址
    const GOOGLE_MAPS_API_KEY = import.meta.env.VITE_GOOGLE_MAPS_API_KEY
    const geocodeUrl = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${latitude},${longitude}&key=${GOOGLE_MAPS_API_KEY}&language=zh-TW`

    const geocodeResponse = await fetch(geocodeUrl)
    const geocodeData = await geocodeResponse.json()

    let formattedAddress = null
    if (geocodeData.results && geocodeData.results.length > 0) {
      formattedAddress = geocodeData.results[0].formatted_address
    }

    // 2. 儲存位置（包含自動取得的地址）
    const { data, error } = await supabase.functions.invoke('save-location', {
      body: {
        latitude,
        longitude,
        type,
        is_primary: isPrimary,
        formatted_address: formattedAddress
      }
    })

    if (error) throw error

    return data.data

  } catch (error) {
    console.error('儲存位置失敗:', error)
    throw error
  }
}
```

**在 Vue 元件中使用：**

```vue
<script setup>
import { ref } from 'vue'
import { saveLocationWithGeocode } from './saveLocationWithGeocode'

const loading = ref(false)
const error = ref(null)
const successMessage = ref(null)

async function handleSaveLocationWithAddress() {
  loading.value = true
  error.value = null
  successMessage.value = null

  try {
    // 取得使用者位置
    const position = await new Promise((resolve, reject) => {
      navigator.geolocation.getCurrentPosition(resolve, reject, {
        enableHighAccuracy: true,
        timeout: 10000
      })
    })

    const { latitude, longitude } = position.coords

    // 儲存位置並自動取得地址
    const result = await saveLocationWithGeocode(latitude, longitude, '家', true)

    successMessage.value = `位置儲存成功！\n地址：${result.formatted_address || '無'}`

  } catch (err) {
    error.value = err.message || '儲存失敗'
  } finally {
    loading.value = false
  }
}
</script>
```

---

## 常見問題

### Q1: 為什麼會收到 "Missing Authorization header" 錯誤？

**A:** 這表示使用者未登入。請確保使用者已登入：

```javascript
// 檢查使用者登入狀態
const { data: { user } } = await supabase.auth.getUser()
if (!user) {
  alert('請先登入才能儲存位置')
  return
}
```

### Q2: 如何處理使用者拒絕位置權限？

**A:** 在 Geolocation 錯誤回調中處理：

```javascript
navigator.geolocation.getCurrentPosition(
  successCallback,
  (error) => {
    if (error.code === 1) { // PERMISSION_DENIED
      alert('請允許網站存取您的位置以使用此功能')
    } else if (error.code === 2) { // POSITION_UNAVAILABLE
      alert('無法取得您的位置，請檢查 GPS 是否開啟')
    } else if (error.code === 3) { // TIMEOUT
      alert('取得位置逾時，請稍後再試')
    }
  }
)
```

### Q3: 可以儲存多個主要地點嗎？

**A:** 不行，系統會自動確保只有一個主要地點。當你儲存一個新的主要地點（`is_primary: true`）時，Edge Function 會自動將其他地點的 `is_primary` 設為 `false`。

### Q4: 如何更新已存在的地點？

**A:** 目前 Edge Function 不支援更新，只能新增。如需更新，可以直接操作資料庫：

```javascript
// 更新地點資訊
await supabase
  .from('locations')
  .update({
    type: '公司',
    is_primary: true,
    formatted_address: '新地址'
  })
  .eq('id', locationId)
  .eq('user_id', user.id) // 確保只能更新自己的地點
```

### Q5: 位置精度如何控制？

**A:** 透過 Geolocation API 的 `enableHighAccuracy` 選項：

```javascript
navigator.geolocation.getCurrentPosition(
  callback,
  errorCallback,
  {
    enableHighAccuracy: true,  // ✅ 高精度（使用 GPS，較慢但準確）
    // enableHighAccuracy: false, // ❌ 低精度（使用 WiFi/Cell，較快但不準）
    timeout: 10000,
    maximumAge: 0
  }
)
```

### Q6: 如何從資料庫讀取並在地圖上顯示儲存的地點？

**A:** 讀取後解析 PostGIS POINT 格式：

```javascript
// 1. 讀取使用者的所有地點
const { data: locations } = await supabase
  .from('locations')
  .select('*')
  .eq('user_id', user.id)

// 2. 解析 PostGIS POINT 格式並顯示
locations.forEach(location => {
  // PostGIS 格式：POINT(longitude latitude)
  const match = location.coordinates.match(/POINT\(([^ ]+) ([^ ]+)\)/)

  if (match) {
    const longitude = parseFloat(match[1])
    const latitude = parseFloat(match[2])

    // 在 Google Maps 上加上標記
    new google.maps.Marker({
      position: { lat: latitude, lng: longitude },
      map: map,
      title: location.type,
      label: location.is_primary ? 'P' : '' // 主要地點標記
    })
  }
})
```

### Q7: 如何測試 Edge Function 是否正常運作？

**A:** 使用瀏覽器開發者工具或 curl：

```bash
# 1. 在瀏覽器開發者工具取得 JWT token
# Application > Local Storage > supabase.auth.token

# 2. 使用 curl 測試
curl -i --location --request POST \
  'https://rsubfpxltwkrdejnvzxw.supabase.co/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_JWT_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{"latitude": 25.0330, "longitude": 121.5654, "type": "家", "is_primary": true}'
```

### Q8: 可以在 Staging 和 Production 之間切換嗎？

**A:** 可以，透過環境變數切換：

```bash
# .env.local (本地開發)
VITE_SUPABASE_URL=http://localhost:54321
VITE_SUPABASE_ANON_KEY=your_local_anon_key

# .env.staging
VITE_SUPABASE_URL=https://rsubfpxltwkrdejnvzxw.supabase.co
VITE_SUPABASE_ANON_KEY=your_staging_anon_key

# .env.production
VITE_SUPABASE_URL=https://your-production-ref.supabase.co
VITE_SUPABASE_ANON_KEY=your_production_anon_key
```

---

## 相關文件

- [Edge Function 架構說明](../backend/ARCHITECTURE.md)
- [Staging 部署指南](../backend/STAGING_DEPLOYMENT.md)
- [Supabase Functions 官方文檔](https://supabase.com/docs/guides/functions)
- [Geolocation API 文檔](https://developer.mozilla.org/en-US/docs/Web/API/Geolocation_API)

---

**最後更新**：2025-10-30
**版本**：1.0.0
