import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 我的收藏 API (Favorite APIs)
// ===================================================================

/**
 * 【更新版】獲取 "當前登入者" 收藏的所有物品
 * (使用 RPC 實現，自動計算距離，回傳結構與 searchItems 相同)
 * @param {object} options - (可選) 排序與分頁
 * @param {number} [options.page=1] - 頁碼
 * @param {number} [options.size=20] - 每頁筆數
 * @param {string} [options.sort_by='favorited_at'] - 排序 ('favorited_at', 'created_at', 'distance', 'price')
 * @param {string} [options.sort_direction='desc'] - 排序方向
 * @returns {Promise<Array | null>} - 回傳收藏物品陣列, 未登入回傳 null
 */
export async function getMyFavoriteItems(options = {}) {
    // 1. 檢查是否已登入 (RPC 內部也會檢查)
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
        console.warn('getMyFavoriteItems: User not logged in.');
        return null;
    }

    // 2. *** 關鍵修改：不再需要 latitude/longitude ***
    //    RPC 會自動從登入者抓取主要地點
    const rpcParams = {
        p_page: options.page || 1,
        p_size: options.size || 20,
        p_sort_by: options.sort_by || 'favorited_at',
        p_sort_direction: options.sort_direction || 'desc'
    };

    // 3. 呼叫 RPC 函式
    const { data, error } = await supabase.rpc('get_my_favorite_items', rpcParams);

    // 4. 錯誤處理
    if (error) {
        console.error('Supabase 獲取 "我的收藏" 失敗:', error);
        throw new Error(error.message);
    }

    // 5. RPC 回傳的 data 就是完美的 DTO，直接回傳
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