import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 聊天 API (Conversation APIs)
// ===================================================================

/**
 * 【功能】獲取 "當前登入者" 的聊天室列表 (前端 select)
 * @param {'buyer' | 'seller' | 'all'} role - 篩選角色 ('buyer', 'seller', 或 'all')
 * @param {object} options - (可選) 分頁
 * @param {number} [options.page=1] - 頁碼
 * @param {number} [options.size=20] - 每頁筆數
 * @returns {Promise<Array | null>} - 回傳聊天室列表, 未登入回傳 null
 */
export async function getMyConversations(role = 'all', options = {}) {
    // 1. 獲取當前登入者
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
        console.warn('getMyConversations: User not logged in.');
        return null;
    }
    const myUserId = user.id;

    // 2. 這是您的 DTO。我們需要 JOIN 物品標題、封面圖、對方暱稱、頭像
    const selectQuery = `
    id,
    item_id,
    buyer_id,
    seller_id,
    updated_at,
    items ( title, image_urls ),
    buyer:users!conversations_buyer_id_fkey ( id, nickname, profile_picture_url ),
    seller:users!conversations_seller_id_fkey ( id, nickname, profile_picture_url )
  `;

    // 3. 處理分頁
    const page = options.page || 1;
    const size = options.size || 20;
    const offset = (page - 1) * size;

    // 4. 建立基礎查詢
    let query = supabase
        .from('conversations')
        .select(selectQuery)
        .order('updated_at', { ascending: false }) // 按最新訊息排序
        .range(offset, offset + size - 1);

    // 5. 根據角色進行篩選
    if (role === 'buyer') {
        query = query.eq('buyer_id', myUserId);
    } else if (role === 'seller') {
        query = query.eq('seller_id', myUserId);
    } else {
        // role === 'all' 或其他值，抓取所有相關的 (RLS 會自動處理權限)
        query = query.or(`buyer_id.eq.${myUserId},seller_id.eq.${myUserId}`);
    }

    // 6. 執行查詢
    const { data, error } = await query;

    // 7. 錯誤處理
    if (error) {
        console.error('Supabase 獲取聊天室列表失敗:', error);
        throw new Error(error.message);
    }

    // 8. (可選) 資料轉換，方便前端使用
    return data.map(convo => {
        // 判斷對方是誰
        const otherUser = convo.buyer_id === myUserId ? convo.seller : convo.buyer;
        return {
            id: convo.id,
            item: {
                id: convo.item_id,
                title: convo.items?.title || '物品已刪除',
                cover_image_url: convo.items?.image_urls?.[0] || null
            },
            other_user: {
                id: otherUser?.id || null,
                nickname: otherUser?.nickname || '未知使用者',
                profile_picture_url: otherUser?.profile_picture_url
            },
            last_updated_at: convo.updated_at
            // 您可能還需要加入 "最新訊息預覽" 和 "未讀訊息數"，這需要更複雜的查詢 (可能需要 RPC)
        };
    });
}

/* data 範例
[
  {
    "id": 51,
    "item": {
      "id": 101,
      "title": "（全新）IKEA 檯燈",
      "cover_image_url": "https://.../item101_cover.jpg"
    },
    "other_user": {
      "id": "b2c3d4e5-xxxx-xxxx-xxxx-user002",
      "nickname": "Amber",
      "profile_picture_url": "https://.../amber.jpg"
    },
    "last_updated_at": "2025-10-19T10:05:00+00:00"
  },
  {
    "id": 48,
    "item": {
      "id": 205,
      "title": "二手登山背包",
      "cover_image_url": "https://.../backpack.png"
    },
    "other_user": {
      "id": "c3d4e5f6-xxxx-xxxx-xxxx-user003",
      "nickname": "Mike",
      "profile_picture_url": null
    },
    "last_updated_at": "2025-10-18T15:30:00+00:00"
  }
  // ... 其他聊天室
]
 */



/**
 * 【功能】獲取指定聊天室的所有訊息 (前端 select)
 * @param {number} conversationId - 要讀取的聊天室 ID
 * @param {object} options - (可選) 分頁 (通常由下往上加載)
 * @param {number} [options.limit=50] - 一次加載的筆數
 * @param {string} [options.before_message_id] - (用於加載更早訊息) 指定加載此 ID 之前的訊息
 * @returns {Promise<Array | null>} - 回傳訊息陣列, 未登入或無權限回傳 null
 */
export async function getConversationMessages(conversationId, options = {}) {
    // 1. 獲取當前登入者 (RLS 需要)
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
        console.warn('getConversationMessages: User not logged in.');
        return null;
    }

    // 2. 這是您的 DTO。只需要訊息本身和發送者 ID
    const selectQuery = `
    id,
    sender_id,
    content,
    is_read,
    sent_at
  `;

    // 3. 處理分頁 (由最新往舊讀取)
    const limit = options.limit || 50;

    // 4. 建立查詢
    let query = supabase
        .from('conversation_messages')
        .select(selectQuery)
        .eq('conversation_id', conversationId) // 篩選聊天室
        .order('sent_at', { ascending: false }) // 從最新排序
        .limit(limit);

    // 5. 如果是加載更早的訊息 (向上滾動)
    if (options.before_message_id) {
        // 找出 'before_message_id' 的時間戳
        const { data: beforeMessage, error: beforeError } = await supabase
            .from('conversation_messages')
            .select('sent_at')
            .eq('id', options.before_message_id)
            .single();
        if (beforeError || !beforeMessage) {
            console.error("找不到 'before_message_id' 的時間戳");
            // 應處理此錯誤，或直接回傳空陣列
        } else {
            query = query.lt('sent_at', beforeMessage.sent_at); // 只抓比它更早的
        }
    }


    // 6. 執行查詢
    const { data, error } = await query;

    // 7. 錯誤處理
    if (error) {
        console.error(`Supabase 獲取訊息 #${conversationId} 失敗:`, error);
        // RLS 錯誤會在這裡被捕捉
        throw new Error(error.message);
    }

    // 8. data 就是訊息陣列 (從最新到最舊)，前端渲染時通常需要反轉
    return data.reverse(); // 反轉成由舊到新，方便 UI 渲染
}

/* data 範例
[
  {
    "id": 1001,
    "sender_id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
    "content": "您好，請問這個檯燈還在嗎？",
    "is_read": true,
    "sent_at": "2025-10-19T10:00:00+00:00"
  },
  {
    "id": 1002,
    "sender_id": "b2c3d4e5-xxxx-xxxx-xxxx-user002",
    "content": "還在喔！",
    "is_read": true,
    "sent_at": "2025-10-19T10:01:00+00:00"
  },
    {
    "id": 1003,
    "sender_id": "b2c3d4e5-xxxx-xxxx-xxxx-user002",
    "content": "有興趣交換嗎？",
    "is_read": false,
    "sent_at": "2025-10-19T10:05:00+00:00"
  }
  // ... 其他訊息
]
 */