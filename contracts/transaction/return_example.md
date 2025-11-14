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