# Map Function 集成指南

本指南說明如何將 Map_Function 地理定位模組集成到主專案中。

## 📋 概覽

Map_Function 是一個獨立的地理定位功能模組，包含：
- **前端**：Vue 3 + Google Maps 地圖介面
- **後端**：Supabase Edge Function 處理位置儲存
- **資料庫**：使用主專案現有的 `locations` 表（PostGIS）

## 🔗 與主專案的關係

### 資料庫層面

Map_Function 複用了主專案的資料庫結構：

```
主專案資料庫 (backend/)
├── locations 表 ✅ 已存在
├── users 表 ✅ 已存在
└── RLS 策略 ✅ 已配置
```

**不需要**執行額外的 Migration，因為：
- `locations` 表已在 `20251025092807_create_initial_schema.sql` 中建立
- RLS 策略已在 `20251025101010_setup_row_level_security.sql` 中設定

### Edge Function 層面

需要將 Edge Function 部署到主專案的 Supabase 實例：

```bash
# 從主專案根目錄
cd Map_Function/backend
./deploy.sh local      # 本地測試
./deploy.sh production # 生產環境
```

### 前端層面

有兩種集成方式：

#### 方式一：作為獨立前端應用
```bash
cd Map_Function/frontend
npm install
npm run dev
```

#### 方式二：集成到現有前端專案
```javascript
// 在您的前端專案中
import LocationMap from './Map_Function/frontend/src/components/LocationMap.vue'

export default {
  components: {
    LocationMap
  }
}
```

## 📁 建議的目錄結構

### 當前結構
```
backend/
├── Map_Function/          # ← 新增的地理定位模組
│   ├── frontend/          # 前端示例代碼
│   ├── backend/           # Edge Function
│   └── README.md
├── supabase/              # 主專案 Supabase 配置
├── database/              # 主專案資料庫函數
└── PROJECT_ARCHITECTURE.md
```

### 建議調整（可選）

如果您有獨立的前端專案，可以將 `Map_Function/frontend` 移動到前端專案中：

```
前端專案/
└── src/
    └── features/
        └── location/      # ← 移動到這裡
            ├── components/
            │   └── LocationMap.vue
            └── supabase.js

後端專案/
└── supabase/
    └── functions/
        └── save-location/ # ← Edge Function 保留在這裡
```

## 🚀 部署清單

### 步驟 1：部署 Edge Function

```bash
# 確保在 Map_Function/backend 目錄
cd Map_Function/backend

# 本地測試
./deploy.sh local

# 部署到遠端（需要替換 project-ref）
# 編輯 deploy.sh，將 YOUR_PRODUCTION_PROJECT_REF 替換為實際值
./deploy.sh production
```

### 步驟 2：驗證部署

```bash
# 測試 Edge Function
curl -i --location --request POST \
  'https://your-project.supabase.co/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_JWT_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{
    "latitude": 25.0330,
    "longitude": 121.5654,
    "type": "家",
    "is_primary": true
  }'
```

### 步驟 3：配置前端

```bash
cd Map_Function/frontend
cp .env.example .env

# 編輯 .env 並填入：
# - VITE_SUPABASE_URL
# - VITE_SUPABASE_ANON_KEY
# - VITE_GOOGLE_MAPS_API_KEY
```

### 步驟 4：測試完整流程

1. 啟動前端開發伺服器：`npm run dev`
2. 註冊/登入使用者
3. 測試位置獲取功能
4. 驗證資料庫中是否成功儲存

## 🔐 環境變數配置

### 前端環境變數

需要在前端專案的 `.env` 檔案中配置：

```env
# Supabase（與主專案相同）
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key

# Google Maps（需要額外申請）
VITE_GOOGLE_MAPS_API_KEY=your-google-maps-api-key
```

### 後端環境變數

Edge Function 會自動使用 Supabase 提供的環境變數：
- `SUPABASE_URL` - 自動注入
- `SUPABASE_SERVICE_ROLE_KEY` - 自動注入

## 📊 資料庫查詢範例

### 查詢使用者的所有地點

```sql
SELECT
    id,
    ST_Y(coordinates::geometry) AS latitude,
    ST_X(coordinates::geometry) AS longitude,
    type,
    is_primary,
    formatted_address,
    created_at
FROM public.locations
WHERE user_id = auth.uid()
ORDER BY is_primary DESC, created_at DESC;
```

### 尋找附近的使用者（用於主專案的物品搜尋）

```sql
-- 結合 search_items RPC 使用
-- 這個功能已在主專案的 search_items() 函數中實現
-- 位置：database/functions/get_searchItems (RPC).sql
```

## 🔄 與主專案功能的整合

### 1. 物品搜尋 (search_items RPC)

主專案的 `search_items()` 函數已經支援基於地理位置的搜尋：

```typescript
// 前端呼叫
const { data, error } = await supabase.rpc('search_items', {
  p_distance_range_km: 5,  // 5公里內
  p_main_category_id: 1,
  p_page: 1,
  p_size: 20
})
```

這個 RPC 會自動：
- 取得當前使用者的主要地點 (`is_primary = true`)
- 計算每個物品與使用者的距離
- 按距離排序結果

### 2. 使用者註冊流程

建議在使用者註冊後，引導使用者設定主要地點：

```javascript
// 註冊完成後
await supabase.functions.invoke('save-location', {
  body: {
    latitude: coords.latitude,
    longitude: coords.longitude,
    type: '家',
    is_primary: true  // 設為主要地點
  }
})
```

### 3. 物品上架流程

上架物品時，可以讓使用者選擇物品所在地點：

```javascript
// 取得使用者的所有地點
const { data: locations } = await supabase
  .from('locations')
  .select('*')
  .eq('user_id', userId)
  .order('is_primary', { ascending: false })

// 讓使用者選擇一個地點，然後上架物品
const { data: item } = await supabase
  .from('items')
  .insert({
    title: '二手筆電',
    location_id: selectedLocationId,  // ← 關聯地點
    // ... 其他欄位
  })
```

## 🧪 測試建議

### 單元測試

測試 Edge Function：

```typescript
// 測試有效座標
const validInput = {
  latitude: 25.0330,
  longitude: 121.5654,
  type: '家',
  is_primary: true
}

// 測試無效座標
const invalidInput = {
  latitude: 999,  // 超出範圍
  longitude: 181,
  type: '家'
}

// 測試未認證請求
// （不提供 Authorization header）
```

### 整合測試

1. **前端 → Edge Function → 資料庫**
   - 測試完整的位置儲存流程
   - 驗證 RLS 策略是否正常運作

2. **地理搜尋功能**
   - 建立多個測試地點
   - 驗證 `search_items` 的距離計算是否正確

3. **主要地點切換**
   - 測試 `is_primary` 標記的自動更新
   - 確保每個使用者只有一個主要地點

## 📝 後續優化建議

### 功能擴展
- [ ] 地址自動完成（Google Places Autocomplete）
- [ ] 地點編輯和刪除功能
- [ ] 地點分享功能
- [ ] 路線規劃（導航到物品所在地）

### 效能優化
- [ ] 地理查詢索引優化
- [ ] Edge Function 快取機制
- [ ] 前端地圖元件懶載入

### 安全性增強
- [ ] 限制每個使用者的地點數量
- [ ] 座標合理性驗證（防止異常座標）
- [ ] 頻率限制（Rate Limiting）

## 🐛 故障排除

### 問題 1：Edge Function 部署失敗

**檢查項目**：
- Supabase CLI 版本是否為 v2.53.6+
- 是否在正確的目錄下執行部署腳本
- `_shared/cors.ts` 檔案是否存在

### 問題 2：前端無法連接 Edge Function

**檢查項目**：
- CORS 設定是否正確
- 前端的 `VITE_SUPABASE_URL` 是否正確
- 使用者是否已登入（是否有有效的 JWT token）

### 問題 3：資料無法儲存

**檢查項目**：
- RLS 策略是否已啟用
- 使用者 ID 是否正確
- Supabase Dashboard 的 Logs 中是否有錯誤訊息

## 📞 技術支援

如有問題，請檢查：
1. [Map_Function/README.md](./README.md) - 完整功能文件
2. [../PROJECT_ARCHITECTURE.md](../PROJECT_ARCHITECTURE.md) - 主專案架構
3. Supabase Dashboard > Logs - 即時錯誤日誌

---

**最後更新**：2025-10-28
**版本**：1.0.0
