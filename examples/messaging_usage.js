/**
 * 訊息功能使用範例
 * 此檔案展示如何在前端應用程式中使用訊息傳遞功能
 */

// 假設已經初始化 Supabase 客戶端
// import { createClient } from '@supabase/supabase-js'
// const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)

// =============================================
// 範例 1: 買家想詢問某個物品
// =============================================

async function startConversationWithSeller(itemId) {
  try {
    // 1. 建立或取得對話
    const { data: conversation, error: convError } = await supabase
      .rpc('create_or_get_conversation', {
        p_item_id: itemId
      });

    if (convError) {
      console.error('建立對話失敗:', convError.message);
      return null;
    }

    // 取得對話資料後繼續

    const conversationId = conversation[0].conversation_id;
    console.log('對話 ID:', conversationId);

    // 2. 發送第一則訊息
    const { data: message, error: msgError } = await supabase
      .rpc('send_message', {
        p_conversation_id: conversationId,
        p_content: '你好，這個物品還有嗎？'
      });

    if (msgError) {
      console.error('發送訊息失敗:', msgError.message);
      return null;
    }

    console.log('訊息已發送:', message);
    return conversationId;
  } catch (error) {
    console.error('錯誤:', error);
    return null;
  }
}

// 導出函數供外部使用
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    startConversationWithSeller
  };
}
