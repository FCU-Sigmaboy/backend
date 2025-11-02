import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 物品搜尋 API (Item Search API)
// ===================================================================

// *** 移除 getCurrentLocation 輔助函式 (如果不再需要) ***
// *** 已更新為使用使用者主要地點計算距離 ***

/**
 * 統一的物品搜尋函式 (RPC)
 * (此函式已更新為使用使用者 "主要地點" 計算距離，不再需要傳入經緯度)
 * @param {object} filters - 篩選條件
 * @param {number} [filters.distance_range_km] - (可選) 搜尋半徑 (公里)
 * @param {number} [filters.main_category_id] - (可選) 主分類 ID
 * @param {number} [filters.sub_category_id] - (可選) 子分類 ID
 * @param {string} [filters.keyword] - (可選) 關鍵字或標籤
 * @param {string} [filters.user_id] - (可選) 特定使用者的 UUID
 * @param {number} [filters.page=1] - 頁碼
 * @param {number} [filters.size=20] - 每頁筆數
 * @param {string} [filters.sort_by='created_at'] - 排序 ('created_at', 'distance', 'price')
 * @param {string} [filters.sort_direction='desc'] - 排序方向 ('asc' 或 'desc')
 * @returns {Promise<Array | null>} - 回傳物品陣列, 未登入回傳 null
 */
export async function searchItems(filters = {}) {

    // 1. 檢查使用者是否登入 (RPC 也會檢查)
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
        console.warn('searchItems: User not logged in.');
        return null; // 或者您可以允許未登入搜尋，但距離會是 NULL
    }

    // 2. 準備傳遞給 RPC 函式的參數
    // *** 不再需要 p_user_latitude, p_user_longitude ***
    const rpcParams = {
        p_distance_range_km: filters.distance_range_km || null,
        p_main_category_id: filters.main_category_id || null,
        p_sub_category_id: filters.sub_category_id || null,
        p_keyword: filters.keyword || null,
        p_user_id: filters.user_id || null,
        p_page: filters.page || 1,
        p_size: filters.size || 20,
        p_sort_by: filters.sort_by || 'created_at',
        p_sort_direction: filters.sort_direction || 'desc'
    };

    // 3. 呼叫 RPC 函式
    const { data, error } = await supabase.rpc('search_items', rpcParams);

    if (error) {
        console.error('Supabase 搜尋物品失敗:', error);
        // 這裡可能會捕捉到 "請先設定您的主要地點" 的錯誤 (如果您選擇方案 A)
        throw new Error(error.message);
    }

    // RPC 回傳的 data 就是完美的 DTO，直接回傳
    return data;
}

/* data 範例
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
    "user": {
      "id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
      "nickname": "Joseph",
      "profile_picture_url": "https://.../joseph.jpg"
    }
  },
  {
    "item_id": 205,
    "title": "二手登山背包",
    "image_url": "https://.../backpack.png",
    "price": 800,
    "distance_km": "4.881",
    "formatted_address": "台中市北屯區文心路",
    "created_at": "2025-10-17T15:00:00.456+00:00",
    "updated_at": "2025-10-17T15:00:00.456+00:00",
    "favorites_count": 5,
    "user": {
      "id": "b2c3d4e5-xxxx-xxxx-xxxx-user002",
      "nickname": "Amber",
      "profile_picture_url": null
    }
  }
]
 */