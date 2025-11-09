/**
 * Conversation API v2 - Supabase RPC 封裝
 * 支援去角色化設計和多商品對話
 */

import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_ANON_KEY
);

/**
 * 建立或取得對話
 * @param {string} otherUserId - 對方用戶 ID
 * @param {number} [initialItemId] - 初始商品 ID (可選)
 * @returns {Promise<Object>} 對話資訊
 *
 * @example
 * const result = await createOrGetConversation('uuid-here', 123);
 * // {
 * //   conversation_id: 456,
 * //   participant_1_id: 'uuid-1',
 * //   participant_2_id: 'uuid-2',
 * //   initial_item_id: 123,
 * //   is_new: true,
 * //   current_user_is_participant_1: false
 * // }
 */
export async function createOrGetConversation(otherUserId, initialItemId = null) {
  const { data, error } = await supabase.rpc('create_or_get_conversation_v2', {
    p_other_user_id: otherUserId,
    p_initial_item_id: initialItemId
  });

  if (error) throw error;
  return data[0];
}

/**
 * 發送訊息
 * @param {number} conversationId - 對話 ID
 * @param {string} content - 訊息內容
 * @param {string} [messageType='text'] - 訊息類型: text, image, system, item_reference
 * @param {number} [relatedItemId] - 關聯商品 ID
 * @returns {Promise<Object>} 訊息資訊
 *
 * @example
 * const message = await sendMessage(456, 'Hello!', 'text', 789);
 * // {
 * //   message_id: 1001,
 * //   conversation_id: 456,
 * //   sender_id: 'current-user-uuid',
 * //   content: 'Hello!',
 * //   message_type: 'text',
 * //   related_item_id: 789,
 * //   created_at: '2024-01-15T10:30:00Z'
 * // }
 */
export async function sendMessage(conversationId, content, messageType = 'text', relatedItemId = null) {
  const { data, error } = await supabase.rpc('send_message_v2', {
    p_conversation_id: conversationId,
    p_content: content,
    p_message_type: messageType,
    p_related_item_id: relatedItemId
  });

  if (error) throw error;
  return data[0];
}

/**
 * 查詢對話列表
 * @param {number} [page=1] - 頁碼
 * @param {number} [size=20] - 每頁筆數
 * @param {boolean} [includeArchived=false] - 是否包含已歸檔
 * @returns {Promise<Array>} 對話列表
 *
 * @example
 * const conversations = await getConversations(1, 20, false);
 * // [
 * //   {
 * //     conversation_id: 456,
 * //     other_user_id: 'uuid-here',
 * //     other_user_name: '張三',
 * //     other_user_avatar: 'https://...',
 * //     initial_item_id: 123,
 * //     initial_item_title: 'iPhone 15 Pro',
 * //     last_message_content: '請問還有嗎?',
 * //     last_message_at: '2024-01-15T10:30:00Z',
 * //     unread_count: 3,
 * //     is_archived: false,
 * //     created_at: '2024-01-10T08:00:00Z'
 * //   }
 * // ]
 */
export async function getConversations(page = 1, size = 20, includeArchived = false) {
  const { data, error } = await supabase.rpc('get_user_conversations_v2', {
    p_page: page,
    p_size: size,
    p_include_archived: includeArchived
  });

  if (error) throw error;
  return data;
}

/**
 * 查詢對話訊息
 * @param {number} conversationId - 對話 ID
 * @param {number} [page=1] - 頁碼
 * @param {number} [size=50] - 每頁筆數
 * @returns {Promise<Array>} 訊息列表
 *
 * @example
 * const messages = await getMessages(456, 1, 50);
 * // [
 * //   {
 * //     message_id: 789,
 * //     sender_id: 'uuid-here',
 * //     sender_name: '張三',
 * //     sender_avatar: 'https://...',
 * //     content: '請問這個商品還有嗎?',
 * //     message_type: 'text',
 * //     related_item_id: null,
 * //     related_item_title: null,
 * //     is_deleted: false,
 * //     is_mine: false,
 * //     is_read: true,
 * //     created_at: '2024-01-15T10:30:00Z'
 * //   }
 * // ]
 */
export async function getMessages(conversationId, page = 1, size = 50) {
  const { data, error } = await supabase.rpc('get_conversation_messages_v2', {
    p_conversation_id: conversationId,
    p_page: page,
    p_size: size,
    p_include_deleted: false
  });

  if (error) throw error;
  return data;
}

/**
 * 標記訊息為已讀
 * @param {number} conversationId - 對話 ID
 * @param {number} [upToMessageId] - 標記到哪個訊息 ID (不提供則全部標記)
 * @returns {Promise<number>} 更新的訊息數量
 *
 * @example
 * const count = await markAsRead(456);
 * // 5 (更新了 5 則訊息)
 */
export async function markAsRead(conversationId, upToMessageId = null) {
  const { data, error } = await supabase.rpc('mark_messages_as_read_v2', {
    p_conversation_id: conversationId,
    p_up_to_message_id: upToMessageId
  });

  if (error) throw error;
  return data;
}

/**
 * 查詢對話中的商品
 * @param {number} conversationId - 對話 ID
 * @returns {Promise<Array>} 商品列表
 *
 * @example
 * const items = await getConversationItems(456);
 * // [
 * //   {
 * //     item_id: 123,
 * //     item_title: 'iPhone 15 Pro',
 * //     item_price: 35000,
 * //     item_image_url: 'https://...',
 * //     item_status: 'available',
 * //     added_by_user_id: 'uuid-here',
 * //     added_by_user_name: '張三',
 * //     added_at: '2024-01-10T08:00:00Z',
 * //     message_count: 15
 * //   }
 * // ]
 */
export async function getConversationItems(conversationId) {
  const { data, error } = await supabase.rpc('get_conversation_items_v2', {
    p_conversation_id: conversationId
  });

  if (error) throw error;
  return data;
}

/**
 * 歸檔或取消歸檔對話
 * @param {number} conversationId - 對話 ID
 * @param {boolean} archived - true=歸檔, false=取消歸檔
 * @returns {Promise<boolean>} 操作是否成功
 *
 * @example
 * await archiveConversation(456, true);  // 歸檔
 * await archiveConversation(456, false); // 取消歸檔
 */
export async function archiveConversation(conversationId, archived = true) {
  const { data, error } = await supabase.rpc('toggle_conversation_archive_v2', {
    p_conversation_id: conversationId,
    p_archived: archived
  });

  if (error) throw error;
  return data;
}

/**
 * Realtime 訂閱新訊息
 * @param {number} conversationId - 對話 ID
 * @param {Function} callback - 收到新訊息時的回調函數
 * @returns {Object} Supabase subscription 物件
 *
 * @example
 * const subscription = subscribeToMessages(456, (message) => {
 *   console.log('New message:', message);
 * });
 *
 * // 取消訂閱
 * subscription.unsubscribe();
 */
export function subscribeToMessages(conversationId, callback) {
  return supabase
    .channel(`conversation_v2_${conversationId}`)
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'conversation_messages_v2',
        filter: `conversation_id=eq.${conversationId}`
      },
      (payload) => callback(payload.new)
    )
    .subscribe();
}

/**
 * 批次取得未讀訊息數量 (輔助函數)
 * @returns {Promise<number>} 總未讀數
 *
 * @example
 * const totalUnread = await getTotalUnreadCount();
 * // 12
 */
export async function getTotalUnreadCount() {
  const conversations = await getConversations(1, 100, false);
  return conversations.reduce((total, conv) => total + conv.unread_count, 0);
}
