/**
 * Conversation API v2 - 訊息類型使用範例
 * 展示如何使用不同類型的訊息功能
 */

import {
  createOrGetConversation,
  sendMessage,
  getMessages,
  getMessageReplies,
} from "../contracts/conversationAPI/conversationAPI_v2.js";

// ============================================================================
// 範例 1: 基本文字訊息
// ============================================================================

async function example1_textMessage() {
  console.log("\n=== 範例 1: 發送文字訊息 ===");

  // 建立或取得對話
  const conversation = await createOrGetConversation(
    "other-user-uuid", // 對方用戶 ID
    123, // 初始商品 ID
  );

  // 發送文字訊息
  const message = await sendMessage(
    conversation.conversation_id,
    "你好！這個商品還有嗎？",
    "text",
  );

  console.log("訊息已發送:", message);
  // 輸出:
  // {
  //   message_id: 1,
  //   conversation_id: 456,
  //   sender_id: 'current-user-uuid',
  //   content: '你好！這個商品還有嗎？',
  //   message_type: 'text',
  //   related_item_id: null,
  //   reply_to_message_id: null,
  //   transaction_id: null,
  //   created_at: '2024-01-15T10:30:00Z'
  // }
}

// ============================================================================
// 範例 2: 圖片訊息
// ============================================================================

async function example2_imageMessage() {
  console.log("\n=== 範例 2: 發送圖片訊息 ===");

  const conversationId = 456;

  // 假設圖片已上傳到 Supabase Storage
  const imageUrl = "https://your-project.supabase.co/storage/v1/object/public/chat-images/photo.jpg";

  const message = await sendMessage(conversationId, imageUrl, "image");

  console.log("圖片訊息已發送:", message);
}

// ============================================================================
// 範例 3: 商品引用訊息
// ============================================================================

async function example3_itemReferenceMessage() {
  console.log("\n=== 範例 3: 發送商品引用訊息 ===");

  const conversationId = 456;

  // 在對話中引用另一個商品
  const message = await sendMessage(
    conversationId,
    "我也有類似的商品，你可以看看這個",
    "item_reference",
    789, // 關聯的商品 ID
  );

  console.log("商品引用訊息已發送:", message);

  // 查詢訊息時會包含商品資訊
  const messages = await getMessages(conversationId);
  console.log("包含商品資訊的訊息:", messages[0]);
  // {
  //   ...
  //   message_type: 'item_reference',
  //   related_item_id: 789,
  //   related_item_title: 'MacBook Pro 2023',
  //   ...
  // }
}

// ============================================================================
// 範例 4: 回覆訊息 (新功能)
// ============================================================================

async function example4_replyMessage() {
  console.log("\n=== 範例 4: 回覆特定訊息 ===");

  const conversationId = 456;

  // 步驟 1: 發送原始訊息
  const originalMessage = await sendMessage(
    conversationId,
    "這個商品可以打折嗎？",
    "text",
  );

  console.log("原始訊息:", originalMessage);

  // 步驟 2: 回覆該訊息
  const replyMessage = await sendMessage(
    conversationId,
    "可以的，我可以給你 9 折優惠！",
    "reply",
    null, // relatedItemId (不需要)
    originalMessage.message_id, // 回覆的訊息 ID
  );

  console.log("回覆訊息已發送:", replyMessage);
  // {
  //   message_id: 2,
  //   conversation_id: 456,
  //   sender_id: 'seller-uuid',
  //   content: '可以的，我可以給你 9 折優惠！',
  //   message_type: 'reply',
  //   related_item_id: null,
  //   reply_to_message_id: 1,
  //   transaction_id: null,
  //   created_at: '2024-01-15T10:31:00Z'
  // }

  // 步驟 3: 查詢訊息時會包含被回覆訊息的資訊
  const messages = await getMessages(conversationId);
  const reply = messages.find((m) => m.message_type === "reply");
  console.log("查詢到的回覆訊息:", reply);
  // {
  //   ...
  //   message_type: 'reply',
  //   reply_to_message_id: 1,
  //   reply_to_content: '這個商品可以打折嗎？',
  //   reply_to_sender_name: '買家名稱',
  //   ...
  // }

  // 步驟 4: 取得特定訊息的所有回覆
  const replies = await getMessageReplies(originalMessage.message_id);
  console.log("該訊息的所有回覆:", replies);
  // [
  //   {
  //     message_id: 2,
  //     sender_id: 'seller-uuid',
  //     sender_name: '賣家名稱',
  //     sender_avatar: 'https://...',
  //     content: '可以的，我可以給你 9 折優惠！',
  //     created_at: '2024-01-15T10:31:00Z'
  //   }
  // ]
}

// ============================================================================
// 範例 5: 交易連結訊息 (新功能)
// ============================================================================

async function example5_transactionLinkMessage() {
  console.log("\n=== 範例 5: 發送交易連結訊息 ===");

  const conversationId = 456;

  // 場景：買家建立了交易
  const transactionId = 1001; // 假設這是剛建立的交易 ID

  // 發送交易連結訊息
  const message = await sendMessage(
    conversationId,
    "交易已建立！交易編號 #1001，請盡快完成付款。",
    "transaction_link",
    123, // 可選：關聯的商品 ID
    null, // replyToMessageId (不需要)
    transactionId, // 交易 ID
  );

  console.log("交易連結訊息已發送:", message);
  // {
  //   message_id: 3,
  //   conversation_id: 456,
  //   sender_id: 'buyer-uuid',
  //   content: '交易已建立！交易編號 #1001，請盡快完成付款。',
  //   message_type: 'transaction_link',
  //   related_item_id: 123,
  //   reply_to_message_id: null,
  //   transaction_id: 1001,
  //   created_at: '2024-01-15T10:32:00Z'
  // }
}

// ============================================================================
// 範例 6: 系統訊息
// ============================================================================

async function example6_systemMessage() {
  console.log("\n=== 範例 6: 發送系統訊息 ===");

  const conversationId = 456;

  // 系統訊息通常由後端自動產生
  const message = await sendMessage(
    conversationId,
    "商品已標記為已售出",
    "system",
  );

  console.log("系統訊息已發送:", message);
}

// ============================================================================
// 範例 7: 複雜場景 - 組合使用
// ============================================================================

async function example7_complexScenario() {
  console.log("\n=== 範例 7: 複雜場景 - 完整對話流程 ===");

  const otherUserId = "other-user-uuid";
  const itemId = 123;

  // 1. 買家發起對話
  const conversation = await createOrGetConversation(otherUserId, itemId);
  console.log("步驟 1: 對話已建立", conversation.conversation_id);

  // 2. 買家詢問商品
  const msg1 = await sendMessage(
    conversation.conversation_id,
    "請問這個商品還有嗎？",
    "text",
  );
  console.log("步驟 2: 買家詢問");

  // 3. 賣家回覆
  const msg2 = await sendMessage(
    conversation.conversation_id,
    "有的！目前還有庫存。",
    "reply",
    null,
    msg1.message_id,
  );
  console.log("步驟 3: 賣家回覆");

  // 4. 買家詢問價格
  const msg3 = await sendMessage(
    conversation.conversation_id,
    "可以打折嗎？",
    "text",
  );
  console.log("步驟 4: 買家詢問價格");

  // 5. 賣家回覆並引用其他商品
  const msg4 = await sendMessage(
    conversation.conversation_id,
    "這個商品不打折，但我有另一個類似的商品比較便宜",
    "item_reference",
    789, // 另一個商品的 ID
  );
  console.log("步驟 5: 賣家推薦其他商品");

  // 6. 買家決定購買原商品
  const msg5 = await sendMessage(
    conversation.conversation_id,
    "還是想買這個，我現在下單",
    "text",
  );
  console.log("步驟 6: 買家決定購買");

  // 7. 系統建立交易並發送連結
  const transactionId = 1001; // 假設系統已建立交易
  const msg6 = await sendMessage(
    conversation.conversation_id,
    "交易已建立！交易編號 #1001",
    "transaction_link",
    itemId,
    null,
    transactionId,
  );
  console.log("步驟 7: 交易連結已發送");

  // 8. 查看完整對話記錄
  const allMessages = await getMessages(conversation.conversation_id);
  console.log("\n完整對話記錄:");
  allMessages.forEach((msg, index) => {
    console.log(`\n訊息 ${index + 1}:`);
    console.log(`  類型: ${msg.message_type}`);
    console.log(`  內容: ${msg.content}`);
    console.log(`  發送者: ${msg.sender_name}`);
    if (msg.reply_to_message_id) {
      console.log(`  回覆: "${msg.reply_to_content}" - ${msg.reply_to_sender_name}`);
    }
    if (msg.related_item_id) {
      console.log(`  關聯商品: ${msg.related_item_title}`);
    }
    if (msg.transaction_id) {
      console.log(`  交易編號: #${msg.transaction_id}`);
    }
  });
}

// ============================================================================
// 範例 8: 錯誤處理
// ============================================================================

async function example8_errorHandling() {
  console.log("\n=== 範例 8: 錯誤處理 ===");

  const conversationId = 456;

  // 錯誤 1: reply 類型沒有提供 reply_to_message_id
  try {
    await sendMessage(conversationId, "回覆", "reply", null, null);
  } catch (error) {
    console.error("錯誤 1:", error.message);
    // 輸出: reply 類型訊息必須指定 reply_to_message_id
  }

  // 錯誤 2: transaction_link 類型沒有提供 transaction_id
  try {
    await sendMessage(
      conversationId,
      "交易",
      "transaction_link",
      null,
      null,
      null,
    );
  } catch (error) {
    console.error("錯誤 2:", error.message);
    // 輸出: transaction_link 類型訊息必須指定 transaction_id
  }

  // 錯誤 3: 回覆不存在的訊息
  try {
    await sendMessage(conversationId, "回覆", "reply", null, 999999);
  } catch (error) {
    console.error("錯誤 3:", error.message);
    // 輸出: 被回覆的訊息必須在同一對話中
  }

  // 錯誤 4: 使用無效的訊息類型
  try {
    await sendMessage(conversationId, "測試", "invalid_type");
  } catch (error) {
    console.error("錯誤 4:", error.message);
    // 輸出: 無效的訊息類型: invalid_type
  }
}

// ============================================================================
// 範例 9: Realtime 訂閱
// ============================================================================

async function example9_realtimeSubscription() {
  console.log("\n=== 範例 9: Realtime 訂閱新訊息 ===");

  const conversationId = 456;

  // 訂閱新訊息
  const subscription = subscribeToMessages(conversationId, (newMessage) => {
    console.log("收到新訊息:", newMessage);

    // 根據訊息類型做不同處理
    switch (newMessage.message_type) {
      case "text":
        console.log("  → 文字訊息");
        break;
      case "image":
        console.log("  → 圖片訊息");
        break;
      case "reply":
        console.log("  → 回覆訊息");
        // 可能需要載入被回覆的訊息資訊
        break;
      case "transaction_link":
        console.log("  → 交易連結訊息");
        // 顯示交易提醒
        break;
      case "item_reference":
        console.log("  → 商品引用訊息");
        break;
      case "system":
        console.log("  → 系統訊息");
        break;
    }
  });

  // 在適當的時候取消訂閱
  // subscription.unsubscribe();
}

// ============================================================================
// 範例 10: 前端 UI 渲染邏輯
// ============================================================================

function example10_renderMessageUI(message) {
  console.log("\n=== 範例 10: 前端渲染邏輯 ===");

  // 根據訊息類型返回不同的 UI 結構
  switch (message.message_type) {
    case "text":
      return {
        type: "bubble",
        content: message.content,
      };

    case "image":
      return {
        type: "image",
        imageUrl: message.content,
      };

    case "reply":
      return {
        type: "reply-bubble",
        replyTo: {
          sender: message.reply_to_sender_name,
          content: message.reply_to_content,
        },
        content: message.content,
      };

    case "transaction_link":
      return {
        type: "transaction-card",
        transactionId: message.transaction_id,
        content: message.content,
        action: "查看交易詳情",
      };

    case "item_reference":
      return {
        type: "item-card",
        itemId: message.related_item_id,
        itemTitle: message.related_item_title,
        content: message.content,
      };

    case "system":
      return {
        type: "system-message",
        content: message.content,
        centered: true,
      };

    default:
      return {
        type: "unknown",
        content: message.content,
      };
  }
}

// ============================================================================
// 執行所有範例
// ============================================================================

async function runAllExamples() {
  try {
    await example1_textMessage();
    await example2_imageMessage();
    await example3_itemReferenceMessage();
    await example4_replyMessage();
    await example5_transactionLinkMessage();
    await example6_systemMessage();
    await example7_complexScenario();
    await example8_errorHandling();
    await example9_realtimeSubscription();

    // 範例 10 是純函數，可以直接呼叫
    const sampleMessage = {
      message_type: "reply",
      content: "同意！",
      reply_to_sender_name: "張三",
      reply_to_content: "這個商品不錯",
    };
    const uiStructure = example10_renderMessageUI(sampleMessage);
    console.log("UI 結構:", uiStructure);

    console.log("\n✅ 所有範例執行完成！");
  } catch (error) {
    console.error("❌ 執行範例時發生錯誤:", error);
  }
}

// 如果直接執行此檔案，則運行所有範例
if (import.meta.url === `file://${process.argv[1]}`) {
  runAllExamples();
}

// 匯出所有範例函數供其他模組使用
export {
  example1_textMessage,
  example2_imageMessage,
  example3_itemReferenceMessage,
  example4_replyMessage,
  example5_transactionLinkMessage,
  example6_systemMessage,
  example7_complexScenario,
  example8_errorHandling,
  example9_realtimeSubscription,
  example10_renderMessageUI,
};
