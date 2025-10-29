# 推薦系統 Edge Functions
# Recommendation System Edge Functions

本目錄包含推薦系統的 Supabase Edge Functions。

## 📁 函數列表

### 1. get-recommendations
獲取個性化推薦物品列表。

**端點**: `POST /functions/v1/get-recommendations`

**請求範例**:
```json
{
  "limit": 20,
  "offset": 0,
  "algorithm": "hybrid",
  "filter": {
    "main_category_id": 1,
    "min_price": 100,
    "max_price": 5000
  }
}
```

**回應範例**:
```json
{
  "success": true,
  "data": {
    "items": [...],
    "total_count": 20,
    "algorithm_used": "hybrid",
    "personalization_level": 75
  }
}
```

### 2. track-interaction
追蹤用戶與物品的互動行為。

**端點**: `POST /functions/v1/track-interaction`

**請求範例**:
```json
{
  "item_id": 123,
  "interaction_type": "view",
  "metadata": {
    "duration_seconds": 30,
    "source": "recommendation",
    "position": 0
  }
}
```

**回應範例**:
```json
{
  "success": true,
  "message": "Interaction tracked successfully",
  "should_update_preferences": false
}
```

### 3. update-preferences
更新用戶偏好設定檔。

**端點**: `POST /functions/v1/update-preferences`

**請求範例**:
```json
{
  "force_recalculate": true,
  "manual_preferences": {
    "preferred_distance_km": 30,
    "max_price_range": 10000
  }
}
```

**回應範例**:
```json
{
  "success": true,
  "message": "Preferences recalculated successfully",
  "preferences": {...}
}
```

## 🚀 部署

### 本地測試

1. 啟動 Supabase 本地環境:
```bash
npx supabase start
```

2. 部署函數到本地:
```bash
npx supabase functions serve get-recommendations
npx supabase functions serve track-interaction
npx supabase functions serve update-preferences
```

3. 測試函數:
```bash
curl -i --location --request POST 'http://localhost:54321/functions/v1/get-recommendations' \
  --header 'Authorization: Bearer YOUR_JWT_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{"limit": 10}'
```

### 部署到生產環境

```bash
# 部署單個函數
npx supabase functions deploy get-recommendations --project-ref your-project-ref

# 部署所有推薦系統函數
npx supabase functions deploy get-recommendations --project-ref your-project-ref
npx supabase functions deploy track-interaction --project-ref your-project-ref
npx supabase functions deploy update-preferences --project-ref your-project-ref
```

## 🔒 安全性

所有 Edge Functions 都需要有效的 JWT token 進行身份驗證。Token 通過 `Authorization: Bearer <token>` header 傳遞。

## 📊 監控

可以在 Supabase Dashboard 中查看函數日誌和效能指標：
- Dashboard > Edge Functions > Logs
- Dashboard > Edge Functions > Invocations

## 🧪 測試

### 使用 Deno 測試

```bash
deno test --allow-all
```

### 使用 curl 測試

參考上面的本地測試部分。

## 📝 開發注意事項

1. **環境變數**: Edge Functions 會自動獲取 `SUPABASE_URL` 和 `SUPABASE_SERVICE_ROLE_KEY`
2. **CORS**: 所有函數都已配置 CORS headers，支持跨域請求
3. **錯誤處理**: 統一的錯誤處理和回應格式
4. **異步操作**: 日誌記錄等非關鍵操作使用異步處理，不阻塞主流程

## 🔗 相關文檔

- [Supabase Edge Functions 官方文檔](https://supabase.com/docs/guides/functions)
- [推薦系統提案文檔](../../contracts/USER_PREFERENCE_RECOMMENDATION_SYSTEM.md)
- [資料庫架構](../../supabase/migrations/)
