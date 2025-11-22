/**
 * ====================================================================
 * ### 建立評價 API (Create Review API)
 * ====================================================================
 *
 * 功能說明：
 * - 允許交易參與者對已完成的交易建立評價
 * - 自動判斷被評價者（交易的另一方）
 * - 每個交易每個評價者只能評價一次
 * - 自動更新被評價者的平均評分
 *
 * 前提條件：
 * - 使用者必須已登入
 * - 交易狀態必須為 'completed'
 * - 評價者必須是交易參與者（giver 或 receiver）
 *
 * Author: Chris
 * Date: 2025-11-06
 * ====================================================================
 */

import { supabase } from '../../lib/supabaseClient.js';

/**
 * 建立評價
 *
 * @param {Object} reviewData - 評價資料
 * @param {number} reviewData.transaction_id - 交易 ID（必填）
 * @param {number} reviewData.score - 評分 1-5（必填）
 * @param {string} [reviewData.comment] - 評論內容（選填）
 * @returns {Promise<Object>} - 回傳建立的評價資訊
 * @throws {Error} - 當評價建立失敗時拋出錯誤
 *
 * @example
 * // 建立評價
 * const result = await createReview({
 *   transaction_id: 1,
 *   score: 5,
 *   comment: '非常好的賣家！商品狀況完美，溝通順暢！'
 * });
 *
 * @example
 * // 只給評分，不留評論
 * const result = await createReview({
 *   transaction_id: 2,
 *   score: 4
 * });
 */
export async function createReview(reviewData) {
  // 1. 驗證必填欄位
  if (!reviewData.transaction_id) {
    throw new Error('缺少必填欄位：transaction_id');
  }

  if (reviewData.score === null || reviewData.score === undefined) {
    throw new Error('缺少必填欄位：score');
  }

  // 2. 驗證評分範圍
  if (reviewData.score < 1 || reviewData.score > 5) {
    throw new Error('評分必須在 1-5 之間');
  }

  // 3. 準備 RPC 參數
  const rpcParams = {
    p_transaction_id: reviewData.transaction_id,
    p_score: reviewData.score,
    p_comment: reviewData.comment || null
  };

  // 4. 呼叫 RPC 函式
  const { data, error } = await supabase.rpc('create_review', rpcParams);

  // 5. 錯誤處理
  if (error) {
    console.error('建立評價失敗:', error);
    throw new Error(error.message);
  }

  // 6. 回傳資料
  if (!data || data.length === 0) {
    throw new Error('評價建立失敗：未回傳資料');
  }

  return data[0]; // 回傳第一筆（唯一）評價記錄
}

/**
 * 檢查是否可以評價某筆交易
 *
 * @param {number} transactionId - 交易 ID
 * @returns {Promise<Object>} - 回傳檢查結果
 * @returns {boolean} canReview - 是否可以評價
 * @returns {string} reason - 無法評價的原因（如果有）
 *
 * @example
 * const check = await canCreateReview(1);
 * if (check.canReview) {
 *   // 顯示評價表單
 * } else {
 *   console.log(check.reason);
 * }
 */
export async function canCreateReview(transactionId) {
  try {
    // 獲取當前使用者
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
      return {
        canReview: false,
        reason: '使用者未登入'
      };
    }

    // 查詢交易資訊
    const { data: transaction, error: txError } = await supabase
      .from('transactions')
      .select('id, giver_id, receiver_id, transaction_status')
      .eq('id', transactionId)
      .single();

    if (txError || !transaction) {
      return {
        canReview: false,
        reason: '交易不存在'
      };
    }

    // 檢查交易狀態
    if (transaction.transaction_status !== 'completed') {
      return {
        canReview: false,
        reason: '只有已完成的交易才能建立評價'
      };
    }

    // 檢查是否為交易參與者
    const isParticipant = user.id === transaction.giver_id || user.id === transaction.receiver_id;
    if (!isParticipant) {
      return {
        canReview: false,
        reason: '您不是此交易的參與者'
      };
    }

    // 檢查是否已經評價過
    const { data: existingReview, error: reviewError } = await supabase
      .from('ratings')
      .select('id')
      .eq('transaction_id', transactionId)
      .eq('reviewer_id', user.id)
      .maybeSingle();

    if (reviewError) {
      console.error('檢查評價失敗:', reviewError);
      return {
        canReview: false,
        reason: '檢查評價狀態失敗'
      };
    }

    if (existingReview) {
      return {
        canReview: false,
        reason: '您已經對此交易建立過評價'
      };
    }

    // 所有檢查通過
    return {
      canReview: true,
      reason: null
    };

  } catch (error) {
    console.error('檢查評價權限失敗:', error);
    return {
      canReview: false,
      reason: '系統錯誤'
    };
  }
}
