import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 追蹤 API (Following APIs)
// ===================================================================

/**
 * 【功能】追蹤指定的使用者 (RPC)
 * @param {string} followingUserId - 您要追蹤的使用者的 UUID
 * @returns {Promise<object>} - 回傳操作結果 (e.g., { success: true, message: '...' })
 */
export async function followUser(followingUserId) {

    // 1. 準備 RPC 參數
    const rpcParams = {
        p_following_id: followingUserId
    };

    // 2. 呼叫 RPC 函式
    const { data, error } = await supabase.rpc('follow_user', rpcParams);

    // 3. 錯誤處理
    if (error) {
        // 這裡會捕捉到 RPC 內部的 RAISE EXCEPTION (例如未登入、追蹤自己)
        console.error(`Supabase 追蹤使用者 #${followingUserId} 失敗:`, error);
        throw new Error(error.message); // 將錯誤往上拋
    }

    // 4. 回傳 RPC 回傳的 JSON 結果
    return data;
}

/* 回傳 data 範例
{
  "success": true,
  "message": "追蹤成功或已追蹤"
}
 */