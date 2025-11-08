import { supabase } from "src/supabaseClient"; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 聊天室 API (Conversation APIs)
// 完全使用 RPC 函式,與後端 Migration 保持一致
//
// 版本: 1.1
// 更新日期: 2025-11-08
// 變更說明:
// - 加強 startChat 的錯誤處理
// - 新增防重複請求機制
// - 新增批次查詢對話功能
// ===================================================================

// ===================================================================
// ### 輔助工具：防重複請求
// ===================================================================

/**
 * 防重複請求的 Promise 快取
 * key: 請求的唯一識別符 (例如: "startChat_123")
 * value: 進行中的 Promise
 */
const pendingRequests = new Map();

/**
 * 【內部函數】防重複請求裝飾器
 * @param {string} key - 請求的唯一識別符
 * @param {Function} requestFn - 實際的請求函數
 * @returns {Promise} - 返回請求結果
 */
async function preventDuplicateRequest(key, requestFn) {
  // 檢查是否有相同的請求正在進行中
  if (pendingRequests.has(key)) {
    console.log(`[防重複] 偵測到重複請求: ${key}, 返回現有 Promise`);
    return pendingRequests.get(key);
  }

  // 建立新的請求 Promise
  const promise = requestFn().finally(() => {
    // 請求完成後，移除快取
    pendingRequests.delete(key);
  });

  // 儲存到快取
  pendingRequests.set(key, promise);

  return promise;
}

// ===================================================================
// ### 聊天室 API 函數
// ===================================================================

/**
 * 【功能】發起聊天 (查找或建立聊天室) (RPC)
 * @param {number} itemId - 您要針對哪個物品發起聊天
 * @returns {Promise<Object>} - 回傳聊天室完整資訊
 * @returns {Promise<{conversation_id: number, item_id: number, buyer_id: string, seller_id: string, created_at: string, updated_at: string}>}
 *
 * 說明：
 * - 使用 UPSERT 機制，併發安全 (透過唯一索引保證)
 * - 如果對話已存在，會更新 updated_at 時間戳記
 * - 資料庫層級防止重複對話建立
 */
export async function startChat(itemId) {
  // 1. 獲取當前登入者 (RPC 內部也會檢查，前端檢查可先擋掉未登入)
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  if (authError || !user) {
    throw new Error("使用者未登入，無法發起聊天");
  }

  // 2. 驗證 itemId
  if (!itemId || itemId <= 0) {
    throw new Error("無效的物品 ID");
  }

  // 3. 準備 RPC 參數
  const rpcParams = {
    p_item_id: itemId,
  };

  // 4. 呼叫 RPC 函式 (已優化支援 ON CONFLICT，併發安全)
  const { data, error } = await supabase.rpc(
    "create_or_get_conversation",
    rpcParams,
  );

  // 5. 錯誤處理
  if (error) {
    // 這裡會捕捉到 RPC 的 RAISE EXCEPTION
    console.error(`Supabase 發起聊天失敗 (Item #${itemId}):`, error);

    // 提供更友善的錯誤訊息
    if (error.message.includes("物品不存在或已下架")) {
      throw new Error("此物品不存在或已下架");
    } else if (error.message.includes("無法與自己的物品建立對話")) {
      throw new Error("無法與自己的物品發起聊天");
    } else if (error.message.includes("使用者未登入")) {
      throw new Error("請先登入");
    } else {
      throw new Error(`發起聊天失敗: ${error.message}`);
    }
  }

  // 6. 驗證回傳資料
  if (!data || data.length === 0) {
    throw new Error("無法建立聊天室，請稍後再試");
  }

  // 7. RPC 回傳的是陣列，取第一筆
  return data[0];
}

/* 回傳 data 範例
{
  "conversation_id": 52,
  "item_id": 101,
  "buyer_id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
  "seller_id": "b2c3d4e5-xxxx-xxxx-xxxx-user002",
  "created_at": "2025-10-19T10:00:00+00:00",
  "updated_at": "2025-10-19T10:00:00+00:00"
}
 */

/**
 * 【功能】發起聊天 (帶防重複請求保護)
 * @param {number} itemId - 您要針對哪個物品發起聊天
 * @returns {Promise<Object>} - 回傳聊天室完整資訊
 */
export async function startChatSafe(itemId) {
  const requestKey = `startChat_${itemId}`;
  return preventDuplicateRequest(requestKey, () => startChat(itemId));
}

/**
 * 【功能】批次查詢對話資訊 (使用新的 RPC 函數，避免 N+1 問題)
 * @param {number[]} conversationIds - 對話 ID 陣列
 * @returns {Promise<Array>} - 回傳對話資訊陣列
 */
export async function getConversationsByIds(conversationIds) {
  // 1. 獲取當前登入者
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  if (authError || !user) {
    console.warn("getConversationsByIds: User not logged in.");
    return null;
  }

  // 2. 驗證參數
  if (!Array.isArray(conversationIds) || conversationIds.length === 0) {
    return [];
  }

  // 3. 準備 RPC 參數
  const rpcParams = {
    p_conversation_ids: conversationIds,
  };

  // 4. 呼叫 RPC 函式
  const { data, error } = await supabase.rpc(
    "get_conversations_by_ids",
    rpcParams,
  );

  // 5. 錯誤處理
  if (error) {
    console.error("Supabase 批次獲取對話失敗:", error);
    throw new Error(error.message);
  }

  // 6. 資料轉換
  return data.map((convo) => ({
    id: convo.conversation_id,
    item: {
      id: convo.item_id,
      title: convo.item_title || "物品已刪除",
      cover_image_url: convo.item_image_url,
    },
    buyer_id: convo.buyer_id,
    seller_id: convo.seller_id,
    created_at: convo.created_at,
    updated_at: convo.updated_at,
  }));
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
    "buyer_id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
    "seller_id": "b2c3d4e5-xxxx-xxxx-xxxx-user002",
    "created_at": "2025-10-19T09:00:00+00:00",
    "updated_at": "2025-10-19T10:05:00+00:00"
  }
]
 */

/**
 * 【功能】獲取 "當前登入者" 的聊天室列表 (RPC)
 * @param {object} options - (可選) 分頁選項
 * @param {number} [options.page=1] - 頁碼
 * @param {number} [options.size=20] - 每頁筆數 (最大 100)
 * @returns {Promise<Array | null>} - 回傳聊天室列表 (包含最新訊息、未讀數), 未登入回傳 null
 */
export async function getMyConversations(options = {}) {
  // 1. 獲取當前登入者
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  if (authError || !user) {
    console.warn("getMyConversations: User not logged in.");
    return null;
  }

  // 2. 準備 RPC 參數
  const page = options.page || 1;
  const size = options.size || 20;

  const rpcParams = {
    p_page: page,
    p_size: size,
  };

  // 3. 呼叫 RPC 函式
  const { data, error } = await supabase.rpc(
    "get_user_conversations",
    rpcParams,
  );

  // 4. 錯誤處理
  if (error) {
    console.error("Supabase 獲取聊天室列表失敗:", error);
    throw new Error(error.message);
  }

  // 5. 資料轉換，統一前端使用的格式
  return data.map((convo) => ({
    id: convo.conversation_id,
    item: {
      id: convo.item_id,
      title: convo.item_title || "物品已刪除",
      cover_image_url: convo.item_image_url,
    },
    other_user: {
      id: convo.other_user_id,
      nickname: convo.other_user_nickname || "未知使用者",
      profile_picture_url: convo.other_user_profile_picture,
    },
    last_message: convo.last_message,
    last_message_time: convo.last_message_time,
    unread_count: parseInt(convo.unread_count) || 0,
    created_at: convo.created_at,
    updated_at: convo.updated_at,
  }));
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
    "last_message": "有興趣交換嗎？",
    "last_message_time": "2025-10-19T10:05:00+00:00",
    "unread_count": 2,
    "created_at": "2025-10-19T09:00:00+00:00",
    "updated_at": "2025-10-19T10:05:00+00:00"
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
    "last_message": "好的謝謝",
    "last_message_time": "2025-10-18T15:30:00+00:00",
    "unread_count": 0,
    "created_at": "2025-10-18T14:00:00+00:00",
    "updated_at": "2025-10-18T15:30:00+00:00"
  }
  // ... 其他聊天室
]
 */

/**
 * 【功能】獲取指定聊天室的所有訊息 (RPC)
 * @param {number} conversationId - 要讀取的聊天室 ID
 * @param {object} options - (可選) 分頁選項
 * @param {number} [options.page=1] - 頁碼
 * @param {number} [options.size=50] - 每頁筆數 (最大 100)
 * @returns {Promise<Array | null>} - 回傳訊息陣列 (包含發送者資訊), 未登入或無權限回傳 null
 */
export async function getConversationMessages(conversationId, options = {}) {
  // 1. 獲取當前登入者 (RLS 需要)
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  if (authError || !user) {
    console.warn("getConversationMessages: User not logged in.");
    return null;
  }

  // 2. 準備 RPC 參數
  const page = options.page || 1;
  const size = options.size || 50;

  const rpcParams = {
    p_conversation_id: conversationId,
    p_page: page,
    p_size: size,
  };

  // 3. 呼叫 RPC 函式
  const { data, error } = await supabase.rpc(
    "get_conversation_messages",
    rpcParams,
  );

  // 4. 錯誤處理
  if (error) {
    console.error(`Supabase 獲取訊息 #${conversationId} 失敗:`, error);
    // RLS 錯誤會在這裡被捕捉 (例如: 無權限查看此對話)
    throw new Error(error.message);
  }

  // 5. 資料轉換，統一前端使用的格式
  return data.map((msg) => ({
    id: msg.message_id,
    sender: {
      id: msg.sender_id,
      nickname: msg.sender_nickname || "未知使用者",
      profile_picture_url: msg.sender_profile_picture,
    },
    content: msg.content,
    is_read: msg.is_read,
    sent_at: msg.sent_at,
  }));
}

/* data 範例
[
  {
    "id": 1001,
    "sender": {
      "id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
      "nickname": "小明",
      "profile_picture_url": "https://.../ming.jpg"
    },
    "content": "您好，請問這個檯燈還在嗎？",
    "is_read": true,
    "sent_at": "2025-10-19T10:00:00+00:00"
  },
  {
    "id": 1002,
    "sender": {
      "id": "b2c3d4e5-xxxx-xxxx-xxxx-user002",
      "nickname": "Amber",
      "profile_picture_url": "https://.../amber.jpg"
    },
    "content": "還在喔！",
    "is_read": true,
    "sent_at": "2025-10-19T10:01:00+00:00"
  },
  {
    "id": 1003,
    "sender": {
      "id": "b2c3d4e5-xxxx-xxxx-xxxx-user002",
      "nickname": "Amber",
      "profile_picture_url": "https://.../amber.jpg"
    },
    "content": "有興趣交換嗎？",
    "is_read": false,
    "sent_at": "2025-10-19T10:05:00+00:00"
  }
  // ... 其他訊息
]
 */

/**
 * 【功能】發送訊息 (RPC)
 * @param {number} conversationId - 要發送訊息的聊天室 ID
 * @param {string} content - 訊息內容
 * @returns {Promise<Object>} - 回傳新建立的訊息
 * @returns {Promise<{message_id: number, sender_id: string, content: string, is_read: boolean, sent_at: string}>}
 */
export async function sendMessage(conversationId, content) {
  // 1. 獲取當前登入者
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  if (authError || !user) {
    throw new Error("使用者未登入，無法發送訊息");
  }

  // 2. 驗證訊息內容
  if (!content || content.trim() === "") {
    throw new Error("訊息內容不能為空");
  }

  // 3. 準備 RPC 參數
  const rpcParams = {
    p_conversation_id: conversationId,
    p_content: content.trim(),
  };

  // 4. 呼叫 RPC 函式
  const { data, error } = await supabase.rpc("send_message", rpcParams);

  // 5. 錯誤處理
  if (error) {
    console.error(
      `Supabase 發送訊息失敗 (Conversation #${conversationId}):`,
      error,
    );
    throw new Error(error.message);
  }

  // 6. RPC 回傳的是陣列，取第一筆
  const message = data[0];
  return {
    id: message.message_id,
    sender_id: message.sender_id,
    content: message.content,
    is_read: message.is_read,
    sent_at: message.sent_at,
  };
}

/* 回傳 data 範例
{
  "id": 1004,
  "sender_id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
  "content": "好的，我們約時間交換吧！",
  "is_read": false,
  "sent_at": "2025-10-19T10:10:00+00:00"
}
 */

/**
 * 【功能】標記訊息為已讀 (RPC)
 * @param {number} conversationId - 要標記的聊天室 ID
 * @returns {Promise<number>} - 回傳更新的訊息數量
 */
export async function markMessagesAsRead(conversationId) {
  // 1. 獲取當前登入者
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  if (authError || !user) {
    throw new Error("使用者未登入，無法標記訊息");
  }

  // 2. 準備 RPC 參數
  const rpcParams = {
    p_conversation_id: conversationId,
  };

  // 3. 呼叫 RPC 函式
  const { data, error } = await supabase.rpc(
    "mark_messages_as_read",
    rpcParams,
  );

  // 4. 錯誤處理
  if (error) {
    console.error(
      `Supabase 標記訊息已讀失敗 (Conversation #${conversationId}):`,
      error,
    );
    throw new Error(error.message);
  }

  // 5. RPC 回傳的是陣列，取第一筆的 updated_count
  return parseInt(data[0]?.updated_count) || 0;
}

/* 回傳 data 範例
5  // 表示有 5 則訊息被標記為已讀
 */

/**
 * 【功能】獲取未讀訊息總數 (RPC)
 * @returns {Promise<number | null>} - 回傳未讀訊息總數, 未登入回傳 null
 */
export async function getUnreadMessageCount() {
  // 1. 獲取當前登入者
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  if (authError || !user) {
    console.warn("getUnreadMessageCount: User not logged in.");
    return null;
  }

  // 2. 呼叫 RPC 函式 (無需參數)
  const { data, error } = await supabase.rpc("get_unread_message_count");

  // 3. 錯誤處理
  if (error) {
    console.error("Supabase 獲取未讀訊息總數失敗:", error);
    throw new Error(error.message);
  }

  // 4. RPC 回傳的是陣列，取第一筆的 unread_count
  return parseInt(data[0]?.unread_count) || 0;
}

/* 回傳 data 範例
12  // 表示目前有 12 則未讀訊息
 */

// ===================================================================
// ### 使用建議與最佳實踐
// ===================================================================

/**
 * 【建議】前端使用範例
 *
 * 1. 發起聊天時使用 startChatSafe 防止重複點擊:
 *    ```js
 *    // ✅ 推薦：自動防重複
 *    const conversation = await startChatSafe(itemId);
 *
 *    // ⚠️ 或手動控制按鈕狀態
 *    setLoading(true);
 *    try {
 *      const conversation = await startChat(itemId);
 *    } finally {
 *      setLoading(false);
 *    }
 *    ```
 *
 * 2. 批次查詢對話避免 N+1 問題:
 *    ```js
 *    // ❌ 避免：逐個查詢
 *    for (const id of conversationIds) {
 *      await getConversationMessages(id);
 *    }
 *
 *    // ✅ 推薦：批次查詢
 *    const conversations = await getConversationsByIds(conversationIds);
 *    ```
 *
 * 3. Realtime 訂閱範例:
 *    ```js
 *    // 訂閱新訊息
 *    const channel = supabase
 *      .channel('conversation_messages')
 *      .on('postgres_changes', {
 *        event: 'INSERT',
 *        schema: 'public',
 *        table: 'conversation_messages',
 *        filter: `conversation_id=eq.${conversationId}`
 *      }, (payload) => {
 *        console.log('New message:', payload.new);
 *      })
 *      .subscribe();
 *    ```
 *
 * 4. 錯誤處理:
 *    ```js
 *    try {
 *      await startChat(itemId);
 *    } catch (error) {
 *      if (error.message.includes('物品不存在')) {
 *        // 處理物品不存在
 *      } else if (error.message.includes('無法與自己的物品')) {
 *        // 處理自己的物品
 *      }
 *    }
 *    ```
 */

// ===================================================================
// ### 變更日誌
// ===================================================================

/**
 * v1.1 (2025-11-08)
 * - ✅ 加強 startChat 錯誤處理（更友善的錯誤訊息）
 * - ✅ 新增 startChatSafe 函數（防重複請求）
 * - ✅ 新增 getConversationsByIds 函數（批次查詢）
 * - ✅ 新增 preventDuplicateRequest 輔助函數
 * - ✅ 新增使用建議文件
 * - ✅ 參數驗證加強
 *
 * v1.0 (2025-10-29)
 * - 初始版本
 * - 基本 CRUD 功能
 */
