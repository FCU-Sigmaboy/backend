====================
見面前
====================

initiateTransaction(itemId, receiverId)

(賣家) 發起交易成功後的回傳：

{
    "transaction_id": 105,
    "status": "confirming",
    "code": "882019"
}

(錯誤範例: Error: 您不是此物品的擁有者)

getMyTransactionsByStatus(status, role)

(買家) 查詢 'confirming' 狀態的交易列表：

[
    {
        "transaction_id": 105,
        "code": "882019",
        "giver_note": "請準時面交喔",
        "receiver_note": null,
        "item_id": 101,
        "item_title": "（全新）IKEA 檯燈",
        "item_image_url": "https://.../item101_cover.jpg",
        "item_price": 500,
        "other_user_id": "a1b2c3d4-xxxx-xxxx-user001",
        "other_user_nickname": "Joseph (賣家)"
    }
]

updateGiverNote(transactionId, note)

(賣家) 更新備註成功後的回傳：

{
    "success": true,
    "giver_note": "請準時面交喔"
}

buyerConfirmTransaction(transactionId, note)

(買家) 確認交易並填寫備註後的回傳：

{
    "success": true,
    "new_status": "pending",
    "receiver_note": "沒問題，謝謝您"
}

(錯誤範例: Error: 點數餘額不足)

cancelTransaction(transactionId)

(任一方) 取消交易成功後的回傳：

{
    "success": true,
    "new_status": "cancelled"
}

(錯誤範例: Error: 此交易狀態無法被取消)




====================
見面，買家輸入code
====================

finalizeTransactionWithCode(transactionId, code)

當您（買家）呼叫 finalizeTransactionWithCode 函式成功執行後（即代碼正確、點數足夠），回傳的 data 變數會是一個 JSON
物件，表示交易成功，並包含更新後的點數餘額。

{
    "success": true,
    "message": "交易完成",
    "transaction_id": 105,
    "new_status": "completed",
    "new_balance": 350
}

如果執行失敗（例如未登入、交易不存在、您不是買家、交易狀態不是 'pending'、確認碼錯誤、點數不足），函式會 throw 一個帶有具體原因的錯誤。

// 範例：執行失敗 (拋出錯誤)
// Error: 確認碼錯誤
// Error: 點數餘額不足
// Error: 此交易並非等待面交確認狀態
