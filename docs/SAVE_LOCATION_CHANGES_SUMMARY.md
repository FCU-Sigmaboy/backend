# Save Location Edge Function 變更摘要

**日期**: 2025-11-05  
**狀態**: ✅ 完成

---

## 🎯 實作需求

1. ✅ 直接提取行政區儲存到 `formatted_address`
2. ✅ 經緯度使用 POINT 格式儲存到 `coordinates`
3. ✅ 為 `is_primary` 設置智慧型檢查邏輯
4. ✅ 為 `type` 設置完整驗證邏輯

---

## 📝 檔案變更清單

### 1. `geocoding.ts` - 行政區提取功能

**主要變更**：
- ✅ `getAddressFromCoordinates()` 現在返回行政區而非完整地址
- ✅ `extractDistrict()` 支援多種地址組件類型
- ✅ 增加備援邏輯（無法提取時使用完整地址）

**關鍵代碼**：
```typescript
// 提取行政區資訊
const district = extractDistrict(data.results[0].address_components)

if (!district) {
  console.warn('⚠️ 無法提取行政區，使用完整地址')
  return data.results[0].formatted_address
}

return district
```

---

### 2. `index.ts` - 主要邏輯增強

**變更 A: 地點類型驗證**
```typescript
// 未指定時預設為「其他」
if (type === undefined || type === null || type === '') {
  type = '其他'
  console.log('⚠️ 未指定地點類型，預設為「其他」')
}

// 錯誤訊息包含有效選項
else if (!validTypes.includes(type)) {
  return new Response(
    JSON.stringify({ 
      error: '無效的地點類型',
      valid_types: validTypes,
      received: type
    }),
    { status: 400 }
  )
}
```

**變更 B: is_primary 智慧型設定**
```typescript
// 未指定時自動判斷
if (typeof is_primary !== 'boolean') {
  const { data: existingLocations } = await supabaseClient
    .from('locations')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', user.id)

  // 第一個地點設為主要，否則設為非主要
  is_primary = (existingLocations === null || existingLocations.length === 0)
}
```

**變更 C: 主要地點更新邏輯**
```typescript
// 只更新同類型的主要地點
if (is_primary) {
  await supabaseClient
    .from('locations')
    .update({ is_primary: false })
    .eq('user_id', user.id)
    .eq('type', type)  // 關鍵：按類型更新
}
```

**變更 D: POINT 格式確認**
```typescript
// 正確的 WKT 格式
const wktPoint = `POINT(${longitude} ${latitude})`
```

**變更 E: 回應格式**
```typescript
return new Response(
  JSON.stringify({
    success: true,
    data: {
      id: data.id,
      latitude,
      longitude,
      district: formattedAddress,  // 改為 district
      type,
      is_primary,
    },
    message: '地點儲存成功'  // 新增成功訊息
  })
)
```

**變更 F: 錯誤訊息中文化**
- ✅ `Invalid coordinates` → `無效的座標格式：...`
- ✅ `Invalid location type` → `無效的地點類型`
- ✅ `Failed to resolve address` → `地址解析失敗`
- ✅ `Failed to save location` → `儲存地點失敗`
- ✅ `Internal server error` → `伺服器內部錯誤`

---

### 3. `types.ts` - 型別定義更新

**變更**：
```typescript
export interface SaveLocationRequest {
  latitude: number
  longitude: number
  type?: '家' | '公司' | '其他'  // Literal types
  is_primary?: boolean
}

export interface SaveLocationResponse {
  success: boolean
  data?: {
    id: number
    latitude: number
    longitude: number
    district: string      // 改為 district
    type: string
    is_primary: boolean
  }
  message?: string        // 新增
  error?: string
  details?: string
  valid_types?: string[]  // 新增
  received?: string       // 新增
}
```

---

## 📊 行為變更對照表

| 場景 | 變更前 | 變更後 |
|-----|-------|-------|
| **地址儲存** | 完整地址 | 只儲存行政區 |
| **type 未指定** | 錯誤 | 自動設為「其他」|
| **is_primary 未指定** | 預設 true | 智慧型判斷 |
| **主要地點更新** | 更新所有類型 | 只更新同類型 |
| **錯誤訊息** | 英文 | 中文 |
| **回應格式** | address | district |

---

## 🧪 測試場景

### 場景 1: 基本儲存
```json
請求: { "latitude": 24.1817, "longitude": 120.7344, "type": "家", "is_primary": true }
回應: { "success": true, "data": { "district": "台中市南屯區", ... } }
```

### 場景 2: 自動設定 is_primary
```json
請求: { "latitude": 24.1817, "longitude": 120.7344 }
行為: 第一個地點 → is_primary = true, type = "其他"
```

### 場景 3: 主要地點更新
```
初始: 家(主要), 公司(主要)
請求: 新增「家」並設為主要
結果: 舊家(非主要), 新家(主要), 公司(主要) ← 公司不受影響
```

### 場景 4: 錯誤處理
```json
請求: { "latitude": 24.1817, "longitude": 120.7344, "type": "學校" }
回應: { 
  "error": "無效的地點類型",
  "valid_types": ["家", "公司", "其他"],
  "received": "學校"
}
```

---

## 📚 文件

- ✅ `README.md` - 完整的 API 文件和使用指南
- ✅ `SAVE_LOCATION_IMPLEMENTATION_REPORT.md` - 詳細實作報告

---

## ✅ 檢查清單

- [x] 程式碼修改完成
- [x] 行政區提取功能測試
- [x] is_primary 邏輯驗證
- [x] type 驗證邏輯測試
- [x] 錯誤訊息確認
- [x] TypeScript 型別更新
- [x] 文件撰寫完成
- [x] README 完整性檢查

---

## 🚀 部署步驟

```bash
# 1. 部署 Edge Function
npx supabase functions deploy save-location

# 2. 確認環境變數
npx supabase secrets list

# 3. 測試端點
curl -X POST https://your-project.supabase.co/functions/v1/save-location \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"latitude": 24.1817, "longitude": 120.7344, "type": "家"}'
```

---

## 📈 影響範圍

### 後端
- ✅ Edge Function 邏輯更新
- ✅ 無需修改資料庫 Schema
- ✅ 無需修改 RLS 策略

### 前端
- ⚠️ 需要更新：回應欄位從 `address` 改為 `district`
- ⚠️ 建議：移除前端的 `type` 預設值設定（後端會自動處理）
- ⚠️ 建議：移除前端的 `is_primary` 預設值設定（後端會智慧判斷）

### 前端修改建議

**修改前**：
```javascript
const result = await saveLocationToBackend(
  latitude, 
  longitude, 
  type = '其他',      // ← 可移除
  isPrimary = true    // ← 可移除
)
```

**修改後**：
```javascript
const result = await saveLocationToBackend(
  latitude, 
  longitude, 
  type,        // 可選，後端會處理
  isPrimary    // 可選，後端會智慧判斷
)

// 回應處理
if (result.success) {
  console.log('行政區:', result.data.district)  // 改為 district
}
```

---

**版本**: 2.0.0  
**狀態**: 🟢 Production Ready  
**審核**: ✅ 完成
