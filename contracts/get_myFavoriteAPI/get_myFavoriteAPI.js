import { supabase } from "src/supabaseClient"; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 我的收藏 API (Favorite APIs) - v2.0 (2025-11-07)
// ===================================================================
// ### Migration v2.0 變更說明：
// ###   - ✅ 已使用 user_id 關聯位置（透過 items.user_id → locations.user_id）
// ###   - ✅ 自動使用賣家的主要地點 (is_primary=true)
// ###   - ✅ 自動使用買家（登入者）的主要地點計算距離
// ###   - ✅ 不再需要傳遞 latitude/longitude 參數
// ###   - ✅ 符合新的資料庫架構（已移除 items.location_id）
// ===================================================================

/**
 * 【v2.0 更新版】獲取 "當前登入者" 收藏的所有物品
 *
 * 🔄 Migration v2.0 更新 (2025-11-07):
 *   - 不再需要傳入經緯度參數
 *   - 自動使用登入者的主要地點計算距離
 *   - 使用 items.user_id 關聯賣家位置（取代舊的 items.location_id）
 *
 * 位置關聯邏輯:
 *   - 買家位置: 自動從 locations 表取得登入者的主要地點
 *   - 賣家位置: items.user_id → locations.user_id (is_primary=true)
 *   - 距離計算: PostGIS ST_Distance 計算買賣雙方主要地點的距離
 *
 * @param {object} options - (可選) 排序與分頁
 * @param {number} [options.page=1] - 頁碼
 * @param {number} [options.size=20] - 每頁筆數
 * @param {string} [options.sort_by='favorited_at'] - 排序 ('favorited_at', 'created_at', 'distance', 'price')
 * @param {string} [options.sort_direction='desc'] - 排序方向
 * @returns {Promise<Array | null>} - 回傳收藏物品陣列, 未登入回傳 null
 */
export async function getMyFavoriteItems(options = {}) {
  // 1. 檢查是否已登入 (RPC 內部也會檢查)
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  if (authError || !user) {
    console.warn("getMyFavoriteItems: User not logged in.");
    return null;
  }

  // 2. ✅ Migration v2.0: 不再需要 latitude/longitude 參數
  //    RPC 會自動從登入者的 locations 表抓取主要地點 (is_primary=true)
  const rpcParams = {
    p_page: options.page || 1,
    p_size: options.size || 20,
    p_sort_by: options.sort_by || "favorited_at",
    p_sort_direction: options.sort_direction || "desc",
  };

  // 3. 呼叫 RPC 函式 (v2.0 - 使用 user_id 關聯位置)
  const { data, error } = await supabase.rpc(
    "get_my_favorite_items",
    rpcParams,
  );

  // 4. 錯誤處理
  if (error) {
    console.error('Supabase 獲取 "我的收藏" 失敗:', error);
    // 可能的錯誤訊息:
    // - "請先設定您的主要地點" (如果使用者沒有任何地點)
    throw new Error(error.message);
  }

  // 5. RPC 回傳的 data 就是完美的 DTO，直接回傳
  // 每個物品的 distance_km 已自動計算（基於買賣雙方的主要地點）
  return data;
}

/* 回傳 data 範例
[
  {
    "item_id": 101,
    "title": "（全新）IKEA 檯燈",
    "image_url": "https://.../item101_cover.jpg",
    "price": 500,
    "distance_km": "1.254",
    "formatted_address": "台中市西屯區福星路",
    "created_at": "2025-10-18T10:30:00.123+00:00",
    "updated_at": "2025-10-18T10:30:00.123+00:00",
    "favorites_count": 15,
    "favorited_at": "2025-10-19T08:00:00+00:00",
    "user": {
      "id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
      "nickname": "Joseph",
      "profile_picture_url": "https://.../joseph.jpg"
    }
  }
  // ... 其他收藏的物品 ...
]
 */
