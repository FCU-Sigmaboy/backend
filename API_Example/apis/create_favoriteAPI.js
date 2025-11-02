import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 收藏 API (Favorite APIs)
// ===================================================================

/**
 * 【功能】將指定物品加入 "當前登入者" 的收藏 (RPC)
 * (包含後端自我收藏檢查)
 * @param {number} itemId - 您要收藏的物品 ID
 * @returns {Promise<object>} - 回傳操作結果 (e.g., { success: true, message: '...' })
 */
export async function addFavoriteItem(itemId) {
    // 1. 獲取當前登入者 ID (雖然 RPC 會做，前端先檢查可以提升體驗)
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
        throw new Error('使用者未登入，無法新增收藏');
    }

    // 2. 準備 RPC 參數
    const rpcParams = {
        p_item_id: itemId
    };

    // 3. *** 關鍵修改：呼叫 RPC 而不是 insert ***
    const { data, error } = await supabase.rpc('add_favorite_item', rpcParams);

    // 4. 錯誤處理
    // // 範例：新增收藏失敗 (拋出錯誤)
    // // Error: User not logged in
    // // Error: Item not found (ID: 999)
    // // Error: Cannot favorite your own item
    // // Error: Network error
    if (error) {
        // 這裡會捕捉到 RPC 內部的 RAISE EXCEPTION (未登入、物品不存在、收藏自己)
        console.error(`Supabase 新增收藏 #${itemId} 失敗:`, error);
        throw new Error(error.message); // 將錯誤往上拋
    }

    // 5. 回傳 RPC 回傳的 JSON 結果
    return data;
}

/* 回傳 data 範例
{
  "success": true,
  "message": "收藏成功或已在收藏中"
}
 */