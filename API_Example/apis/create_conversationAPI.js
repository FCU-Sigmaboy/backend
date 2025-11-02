import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 聊天 API (Conversation APIs) - 續
// ===================================================================

/**
 * 【新功能】發起聊天 (查找或建立聊天室) (RPC)
 * @param {number} itemId - 您要針對哪個物品發起聊天
 * @returns {Promise<{conversation_id: number}>} - 回傳包含聊天室 ID 的物件
 */
export async function startChat(itemId) {
    // 1. 獲取當前登入者 (RPC 內部也會檢查，前端檢查可先擋掉未登入)
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
        throw new Error('使用者未登入，無法發起聊天');
    }

    // 2. 準備 RPC 參數
    const rpcParams = {
        p_item_id: itemId
    };

    // 3. 呼叫 RPC 函式
    const { data, error } = await supabase.rpc('find_or_create_conversation', rpcParams);

    // 4. 錯誤處理
    if (error) {
        // 這裡會捕捉到 RPC 的 RAISE EXCEPTION
        console.error(`Supabase 發起聊天失敗 (Item #${itemId}):`, error);
        throw new Error(error.message);
    }

    // 5. 回傳 RPC 回傳的 JSON 結果
    return data;
}

/* 回傳 data 範例
當您呼叫 `startChat` 函式成功執行後（無論是找到現有聊天室還是建立了新的），回傳的 `data` 變數會是一個 JSON 物件，包含了對應的 `conversation_id`。
前端通常會使用這個 ID 跳轉到聊天頁面 (`/chat/{conversation_id}`)。
{
  "conversation_id": 52
}
 */

