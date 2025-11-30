/**
 * ============================================
 * 檔案: dailySignIn.js
 * 用途: 每日簽到系統前端 Contract
 * ============================================
 *
 * 版本歷史:
 * - V1.0 (2025-11-01) - 初始版本
 * - V2.0 (2025-11-15) - 優化連續簽到獎勵邏輯
 * - V3.0 (2025-11-25) - 新增里程碑獎勵系統
 * - V4.0 (2025-12-01) - 整合徽章系統，簽到後自動檢查並授予徽章
 *
 * 對應後端 RPC:
 * - daily_check_in() (V4)
 *
 * 獎勵規則:
 * - 每日簽到: 5 點
 * - 連續 3 天: 10 點
 * - 連續 7 天: 20 點
 * - 連續 14 天: 30 點
 * - 連續 30 天: 50 點
 * - 連續 100 天: 200 點
 * ============================================
 */

import { supabase } from 'src/supabaseClient';

/**
 * 執行每日簽到 (RPC V4)
 * - 自動計算連續簽到天數
 * - 發放對應點數獎勵
 * - 自動檢查並授予徽章
 * - 回傳新獲得的徽章資訊
 *
 * @returns {Promise<object>} - 簽到結果 (含徽章資訊)
 * @throws {Error} - 使用者未登入或 RPC 執行失敗
 */
export async function dailySignIn() {
    // 1. 檢查使用者是否登入
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('使用者未登入');

    // 2. 呼叫 RPC 函式（V4 版本，含徽章系統整合）
    const { data, error } = await supabase.rpc('daily_check_in');

    // 3. 錯誤處理
    if (error) {
        console.error('Supabase 每日簽到失敗:', error);
        throw new Error(error.message);
    }

    // 4. 回傳 RPC 結果（含徽章資訊）
    return data;
}

/**
 * ============================================
 * 回傳資料範例 (V4 版本 - 含徽章系統)
 * ============================================
 *
 * 情境 1：簽到成功 (連續第 8 天，無新徽章)
 * {
 *   "success": true,
 *   "message": "簽到成功！",
 *   "points_awarded": 5,
 *   "streak_day": 8,
 *   "next_reward": 6,
 *   "new_balance": 1005,
 *   "badges": {
 *     "newly_earned_count": 0,
 *     "total_points_awarded": 0,
 *     "badges": null
 *   }
 * }
 *
 * 情境 2：簽到成功 (連續第 7 天 - 觸發獎勵 + 獲得徽章)
 * {
 *   "success": true,
 *   "message": "簽到成功！",
 *   "points_awarded": 20,
 *   "streak_day": 7,
 *   "next_reward": 7,
 *   "new_balance": 1070,
 *   "badges": {
 *     "newly_earned_count": 1,
 *     "total_points_awarded": 50,
 *     "badges": [
 *       {
 *         "badge_id": "streak_7",
 *         "name": "連續簽到達人",
 *         "icon": "🔥",
 *         "description": "連續簽到7天",
 *         "rarity": "Common",
 *         "points_reward": 50
 *       }
 *     ]
 *   }
 * }
 *
 * 情境 3：簽到成功 (連續第 3 天 - 觸發獎勵)
 * {
 *   "success": true,
 *   "message": "簽到成功！",
 *   "points_awarded": 10,
 *   "streak_day": 3,
 *   "next_reward": 4,
 *   "new_balance": 810,
 *   "badges": {
 *     "newly_earned_count": 0,
 *     "total_points_awarded": 0,
 *     "badges": null
 *   }
 * }
 *
 * 情境 4：今天已簽到過
 * {
 *   "success": false,
 *   "message": "您今天已經簽到過了",
 *   "points_awarded": 0,
 *   "streak_day": 8,
 *   "next_reward": 6
 * }
 *
 * ============================================
 * 使用範例
 * ============================================
 *
 * // 範例 1: 執行每日簽到
 * try {
 *   const result = await dailySignIn();
 *
 *   if (result.success) {
 *     console.log(`簽到成功！獲得 ${result.points_awarded} 點數`);
 *     console.log(`連續簽到 ${result.streak_day} 天`);
 *     console.log(`新餘額: ${result.new_balance}`);
 *
 *     // 檢查是否獲得新徽章
 *     if (result.badges && result.badges.newly_earned_count > 0) {
 *       console.log(`恭喜！獲得 ${result.badges.newly_earned_count} 個新徽章`);
 *       console.log(`徽章獎勵點數: ${result.badges.total_points_awarded}`);
 *       result.badges.badges.forEach(badge => {
 *         console.log(`${badge.icon} ${badge.name} - ${badge.description}`);
 *       });
 *     }
 *   } else {
 *     console.log(result.message); // "���今天已經簽到過了"
 *   }
 * } catch (error) {
 *   console.error('簽到失敗:', error.message);
 * }
 *
 * // 範例 2: 顯示距離下次獎勵的天數
 * const result = await dailySignIn();
 * if (result.success && result.next_reward > 0) {
 *   console.log(`再簽到 ${result.next_reward} 天即可獲得獎勵`);
 * }
 *
 * ============================================
 */