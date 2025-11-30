/**
 * ============================================
 * 檔案: getUserBadgesWithProgress.js
 * 用途: 徽章系統前端 Contract
 * ============================================
 *
 * 版本歷史:
 * - V1.0 (2025-12-01)
 *   - 初始版本
 *   - 支援獲取使用者已獲得徽章列表
 *   - 支援獲取使用者進行中徽章進度
 *   - 支援手動觸發徽章檢查
 *
 * 對應後端 RPC:
 * - get_user_badges_with_progress(p_user_id UUID)
 * - manually_check_badges()
 *
 * 徽章類別 (category):
 * - streak: 連續簽到
 * - transaction: 交易成就
 * - points: 點數累積
 * - carbon: 環保貢獻
 * - seasonal: 季節性活動
 *
 * 稀有度 (rarity):
 * - Common: 普通
 * - Uncommon: 罕見
 * - Rare: 稀有
 * - Epic: 史詩
 * - Legendary: 傳說
 * ============================================
 */

import { supabase } from 'src/supabaseClient';

/**
 * 獲取使用者的徽章列表（包含進度）
 * - 自動同步最新進度
 * - 回傳已獲得徽章 (依獲得時間排序)
 * - 回傳進行中徽章 (依完成度排序)
 *
 * @param {string|null} userId - 使用者 ID (null = 當前使用者)
 * @returns {Promise<object>} - 徽章資料物件
 * @throws {Error} - 使用者未登入或 RPC 執行失敗
 */
export async function getUserBadgesWithProgress(userId = null) {
    // 呼叫 RPC 函式
    const { data, error } = await supabase.rpc('get_user_badges_with_progress', {
        p_user_id: userId
    });

    // 錯誤處理
    if (error) {
        console.error('獲取徽章失敗:', error);
        throw new Error(error.message);
    }

    return data;
}

/**
 * 手動觸發徽章檢查與授予
 * - 檢查當前使用者是否達成新徽章條件
 * - 自動授予達成的徽章並發放點數獎勵
 * - 回傳新獲得的徽章資訊
 *
 * @returns {Promise<object>} - 新獲得徽章資訊
 * @throws {Error} - 使用者未登入或 RPC 執行失敗
 */
export async function manuallyCheckBadges() {
    // 檢查使用者登入狀態
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('使用者未登入');

    // 呼叫 RPC 函式
    const { data, error } = await supabase.rpc('manually_check_badges');

    // 錯誤處理
    if (error) {
        console.error('檢查徽章失敗:', error);
        throw new Error(error.message);
    }

    return data;
}

/**
 * ============================================
 * 回傳資料範例
 * ============================================
 *
 * getUserBadgesWithProgress() 回傳範例:
 * {
 *   "user_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
 *   "earned_badges": [
 *     {
 *       "badge_id": "streak_7",
 *       "name": "連續簽到達人",
 *       "icon": "🔥",
 *       "description": "連續簽到7天",
 *       "rarity": "Common",
 *       "category": "streak",
 *       "points_reward": 20,
 *       "earned_at": "2025-11-30T10:00:00+00:00"
 *     },
 *     {
 *       "badge_id": "first_sale",
 *       "name": "首次賣出",
 *       "icon": "💰",
 *       "description": "完成第一筆銷售",
 *       "rarity": "Common",
 *       "category": "transaction",
 *       "points_reward": 10,
 *       "earned_at": "2025-11-29T15:30:00+00:00"
 *     }
 *   ],
 *   "in_progress_badges": [
 *     {
 *       "badge_id": "streak_14",
 *       "name": "雙週堅持者",
 *       "icon": "⭐",
 *       "description": "連續簽到14天",
 *       "rarity": "Uncommon",
 *       "category": "streak",
 *       "points_reward": 30,
 *       "current_value": 10,
 *       "target_value": 14,
 *       "percentage": 71.43
 *     },
 *     {
 *       "badge_id": "seller_10",
 *       "name": "優質賣家",
 *       "icon": "🏆",
 *       "description": "完成10筆銷售",
 *       "rarity": "Uncommon",
 *       "category": "transaction",
 *       "points_reward": 50,
 *       "current_value": 3,
 *       "target_value": 10,
 *       "percentage": 30.00
 *     }
 *   ]
 * }
 *
 * ============================================
 *
 * manuallyCheckBadges() 回傳範例:
 * {
 *   "newly_earned_count": 2,
 *   "total_points_awarded": 50,
 *   "badges": [
 *     {
 *       "badge_id": "streak_14",
 *       "name": "雙週堅持者",
 *       "icon": "⭐",
 *       "description": "連續簽到14天",
 *       "rarity": "Uncommon",
 *       "points_reward": 30
 *     },
 *     {
 *       "badge_id": "first_purchase",
 *       "name": "首次購買",
 *       "icon": "🛒",
 *       "description": "完成第一筆購買",
 *       "rarity": "Common",
 *       "points_reward": 20
 *     }
 *   ]
 * }
 *
 * ============================================
 * 使用範例
 * ============================================
 *
 * // 範例 1: 獲取當前使用者的徽章
 * try {
 *   const result = await getUserBadgesWithProgress();
 *   console.log('已獲得:', result.earned_badges);
 *   console.log('進行中:', result.in_progress_badges);
 * } catch (error) {
 *   console.error('錯誤:', error.message);
 * }
 *
 * // 範例 2: 獲取特定使用者的徽章（例如查看其他人的成就）
 * try {
 *   const otherUserId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
 *   const result = await getUserBadgesWithProgress(otherUserId);
 *   console.log('該使用者的徽章:', result.earned_badges);
 * } catch (error) {
 *   console.error('錯誤:', error.message);
 * }
 *
 * // 範例 3: 手動檢查是否獲得新徽章（例如在完成重要操作後）
 * try {
 *   const result = await manuallyCheckBadges();
 *   if (result.newly_earned_count > 0) {
 *     console.log(`恭喜！獲得 ${result.newly_earned_count} 個新徽章`);
 *     console.log(`獲得 ${result.total_points_awarded} 點數獎勵`);
 *     result.badges.forEach(badge => {
 *       console.log(`${badge.icon} ${badge.name}`);
 *     });
 *   }
 * } catch (error) {
 *   console.error('錯誤:', error.message);
 * }
 *
 * ============================================
 */

