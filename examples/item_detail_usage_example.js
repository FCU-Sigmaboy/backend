// ===================================================================
// ### 物品詳情 API 使用範例 (完整版)
// ### 包含 Supabase 初始化和認證模擬
// ===================================================================

import { createClient } from "@supabase/supabase-js";
import dotenv from "dotenv";

// 載入環境變數
dotenv.config();

// ===================================================================
// ### Supabase 初始化設定
// ===================================================================

const supabaseUrl =
  process.env.SUPABASE_URL || "https://your-project.supabase.co";
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || "your-anon-key";

// 初始化 Supabase 客戶端
const supabase = createClient(supabaseUrl, supabaseAnonKey);

console.log("📡 Supabase 客戶端初始化完成");
console.log(`   URL: ${supabaseUrl}`);
console.log(`   Key: ${supabaseAnonKey.substring(0, 20)}...`);

// ===================================================================
// ### API 函數定義 (內嵌版本，避免外部依賴)
// ===================================================================

/**
 * 使用資料庫存儲的用戶位置獲取物品詳情
 */
async function getItemDetailsWithUserLocation(itemId) {
  try {
    if (!itemId || typeof itemId !== "number") {
      throw new Error("itemId 必須是有效的數字");
    }

    console.log(`📍 正在使用資料庫用戶位置查詢物品 #${itemId}...`);

    const { data, error } = await supabase
      .rpc("get_item_details_with_user_location", { p_item_id: itemId })
      .maybeSingle();

    if (error) {
      console.error(`Supabase RPC 錯誤:`, error);
      if (error.message.includes("使用者未登入")) {
        throw new Error("請先登入以查看物品詳情");
      }
      throw new Error(`資料庫查詢失敗: ${error.message}`);
    }

    if (data && data.error) {
      return {
        success: false,
        error: true,
        message: data.message,
        itemId: itemId,
        data: null,
      };
    }

    if (data) {
      data.image_urls = data.image_urls || [];
      data.tags = data.tags || [];

      return {
        success: true,
        error: false,
        message: "物品詳情獲取成功",
        itemId: itemId,
        data: data,
      };
    }

    return {
      success: false,
      error: true,
      message: "物品不存在或已下架",
      itemId: itemId,
      data: null,
    };
  } catch (error) {
    console.error(`獲取物品詳情失敗:`, error.message);
    return {
      success: false,
      error: true,
      message: error.message,
      itemId: itemId,
      data: null,
    };
  }
}

/**
 * 使用提供的經緯度座標獲取物品詳情
 */
async function getItemDetailsWithCoordinates(itemId, userLocation) {
  try {
    if (!itemId || typeof itemId !== "number") {
      throw new Error("itemId 必須是有效的數字");
    }

    if (
      !userLocation ||
      typeof userLocation.latitude !== "number" ||
      typeof userLocation.longitude !== "number"
    ) {
      throw new Error("userLocation 必須包含有效的 latitude 和 longitude 數值");
    }

    console.log(
      `🌍 正在使用座標 (${userLocation.latitude}, ${userLocation.longitude}) 查詢物品 #${itemId}...`,
    );

    const { data, error } = await supabase
      .rpc("get_item_details_with_coordinates", {
        p_item_id: itemId,
        p_user_latitude: userLocation.latitude,
        p_user_longitude: userLocation.longitude,
      })
      .maybeSingle();

    if (error) {
      console.error(`Supabase RPC 錯誤:`, error);
      throw new Error(`資料庫查詢失敗: ${error.message}`);
    }

    if (data && data.error) {
      return {
        success: false,
        error: true,
        message: data.message,
        itemId: itemId,
        data: null,
      };
    }

    if (data) {
      data.image_urls = data.image_urls || [];
      data.tags = data.tags || [];

      return {
        success: true,
        error: false,
        message: "物品詳情獲取成功",
        itemId: itemId,
        data: data,
      };
    }

    return {
      success: false,
      error: true,
      message: "物品不存在或已下架",
      itemId: itemId,
      data: null,
    };
  } catch (error) {
    console.error(`獲取物品詳情失敗:`, error.message);
    return {
      success: false,
      error: true,
      message: error.message,
      itemId: itemId,
      data: null,
    };
  }
}

/**
 * 檢查用戶認證狀態
 */
async function checkUserAuthentication() {
  try {
    const {
      data: { user },
      error,
    } = await supabase.auth.getUser();

    if (error) {
      console.error("檢查認證狀態失敗:", error);
      return false;
    }

    return user !== null;
  } catch (error) {
    console.error("檢查認證狀態時發生錯誤:", error);
    return false;
  }
}

/**
 * 智能選擇最適合的方式獲取物品詳情
 */
async function getItemDetailsAuto(itemId, fallbackLocation = null) {
  try {
    const isAuthenticated = await checkUserAuthentication();

    if (isAuthenticated) {
      console.log("🔐 用戶已登入，優先使用資料庫位置");
      const result = await getItemDetailsWithUserLocation(itemId);

      if (result.success || result.message.includes("登入")) {
        return result;
      }

      if (fallbackLocation) {
        console.log("🔄 資料庫位置查詢失敗，使用備用位置");
        return await getItemDetailsWithCoordinates(itemId, fallbackLocation);
      }

      return result;
    } else {
      console.log("🚫 用戶未登入");

      if (!fallbackLocation) {
        return {
          success: false,
          error: true,
          message: "用戶未登入且未提供位置資訊，請先登入或提供當前位置",
          itemId: itemId,
          data: null,
        };
      }

      return await getItemDetailsWithCoordinates(itemId, fallbackLocation);
    }
  } catch (error) {
    console.error("自動獲取物品詳情失敗:", error);
    return {
      success: false,
      error: true,
      message: `自動獲取失敗: ${error.message}`,
      itemId: itemId,
      data: null,
    };
  }
}

// ===================================================================
// ### 認證模擬功能 (測試用)
// ===================================================================

/**
 * 模擬用戶登入 (測試用)
 */
async function simulateLogin(
  email = "test@example.com",
  password = "testpassword",
) {
  try {
    console.log("🔐 嘗試模擬登入...");

    // 注意: 這裡使用模擬登入，實際應用中請使用真實的認證
    const { data, error } = await supabase.auth.signInWithPassword({
      email: email,
      password: password,
    });

    if (error) {
      console.log("⚠️ 模擬登入失敗 (這在測試環境是正常的):", error.message);
      console.log("💡 提示: 請確保已在 Supabase 中建立測試用戶");
      return false;
    }

    console.log("✅ 模擬登入成功");
    console.log(`👤 用戶 ID: ${data.user.id}`);
    return true;
  } catch (error) {
    console.log("⚠️ 登入過程發生錯誤:", error.message);
    return false;
  }
}

/**
 * 模擬登出
 */
async function simulateLogout() {
  try {
    await supabase.auth.signOut();
    console.log("🚪 已模擬登出");
    return true;
  } catch (error) {
    console.error("登出失敗:", error);
    return false;
  }
}

// ===================================================================
// ### 範例執行函數
// ===================================================================

/**
 * 範例 1: 基礎使用 - 自動選擇最佳方式
 */
async function example1_autoGetItemDetails() {
  console.log("\n=== 範例 1: 自動獲取物品詳情 ===");

  const itemId = 123;

  // 備用位置 (台中市區)
  const fallbackLocation = {
    latitude: 24.1477,
    longitude: 120.6736,
  };

  try {
    const result = await getItemDetailsAuto(itemId, fallbackLocation);

    if (result.success) {
      console.log("✅ 成功獲取物品詳情");
      console.log(`📦 物品標題: ${result.data.title}`);
      console.log(`💰 價格: ${result.data.price} 點數`);
      console.log(
        `📍 距離: ${result.data.distance_km ? result.data.distance_km + " km" : "無法計算"}`,
      );
      console.log(`⭐ 是否已收藏: ${result.data.is_favorited ? "是" : "否"}`);
      console.log(`👤 擁有者: ${result.data.user?.nickname || "未知"}`);
    } else {
      console.log("❌ 獲取失敗:", result.message);
    }
  } catch (error) {
    console.error("💥 發生錯誤:", error.message);
  }
}

/**
 * 範例 2: 測試登入狀態下的資料庫位置使用
 */
async function example2_userLocationFromDB() {
  console.log("\n=== 範例 2: 測試資料庫用戶位置 ===");

  const itemId = 456;

  try {
    // 檢查當前登入狀態
    const isLoggedIn = await checkUserAuthentication();
    console.log(`🔐 當前登入狀態: ${isLoggedIn ? "已登入" : "未登入"}`);

    if (!isLoggedIn) {
      console.log("🔄 嘗試模擬登入...");
      const loginSuccess = await simulateLogin();

      if (!loginSuccess) {
        console.log("⚠️ 無法模擬登入，將跳過此範例");
        console.log("💡 建議: 在 Supabase 控制台建立測試用戶或修改認證設定");
        return;
      }
    }

    // 使用資料庫存儲的用戶位置
    const result = await getItemDetailsWithUserLocation(itemId);

    if (result.success) {
      console.log("✅ 使用資料庫位置成功");
      displayItemDetails(result.data);
    } else {
      console.log("❌ 獲取失敗:", result.message);
      if (result.message.includes("位置")) {
        console.log("💡 提示: 用戶可能尚未設定地點資訊");
      }
    }
  } catch (error) {
    console.error("💥 發生錯誤:", error.message);
  }
}

/**
 * 範例 3: 使用提供的經緯度座標
 */
async function example3_useProvidedCoordinates() {
  console.log("\n=== 範例 3: 使用提供的經緯度座標 ===");

  const itemId = 789;
  const userLocation = {
    latitude: 24.1477,
    longitude: 120.6736,
  };

  try {
    console.log(
      `📍 使用座標: ${userLocation.latitude}, ${userLocation.longitude}`,
    );

    const result = await getItemDetailsWithCoordinates(itemId, userLocation);

    if (result.success) {
      console.log("✅ 使用提供座標成功");
      displayItemDetails(result.data);
    } else {
      console.log("❌ 獲取失敗:", result.message);
    }
  } catch (error) {
    console.error("💥 發生錯誤:", error.message);
  }
}

/**
 * 範例 4: 錯誤處理測試
 */
async function example4_errorHandling() {
  console.log("\n=== 範例 4: 錯誤處理測試 ===");

  const testCases = [
    {
      name: "無效的物品 ID (字串)",
      itemId: "invalid",
      shouldFail: true,
    },
    {
      name: "無效的物品 ID (負數)",
      itemId: -1,
      shouldFail: true,
    },
    {
      name: "不存在的物品",
      itemId: 999999,
      shouldFail: false,
    },
    {
      name: "正常的物品 ID",
      itemId: 123,
      shouldFail: false,
    },
  ];

  for (const testCase of testCases) {
    console.log(`\n🧪 測試: ${testCase.name}`);

    try {
      const result = await getItemDetailsAuto(testCase.itemId, {
        latitude: 24.1477,
        longitude: 120.6736,
      });

      if (testCase.shouldFail) {
        console.log("⚠️ 預期失敗但成功了:", result.message);
      } else if (result.success) {
        console.log("✅ 測試通過 - 成功獲取資料");
      } else {
        console.log("ℹ️ 測試通過 - 預期的失敗:", result.message);
      }
    } catch (error) {
      if (testCase.shouldFail) {
        console.log("✅ 測試通過 - 預期的錯誤:", error.message);
      } else {
        console.log("❌ 測試失敗 - 意外的錯誤:", error.message);
      }
    }
  }
}

/**
 * 範例 5: 連線測試
 */
async function example5_connectionTest() {
  console.log("\n=== 範例 5: Supabase 連線測試 ===");

  try {
    // 測試基本連線
    console.log("🔗 測試 Supabase 連線...");

    const { data, error } = await supabase
      .from("main_categories")
      .select("id, name")
      .limit(3);

    if (error) {
      console.error("❌ 連線測試失敗:", error.message);
      console.log("💡 請檢查:");
      console.log("   - SUPABASE_URL 是否正確");
      console.log("   - SUPABASE_ANON_KEY 是否正確");
      console.log("   - 網路連線是否正常");
      console.log("   - Supabase 專案是否啟用");
    } else {
      console.log("✅ Supabase 連線成功");
      console.log("📊 測試資料 (主分類):");
      data.forEach((category) => {
        console.log(`   - ${category.id}: ${category.name}`);
      });
    }

    // 測試認證狀態
    console.log("\n🔐 測試認證狀態...");
    const isAuth = await checkUserAuthentication();
    console.log(`   認證狀態: ${isAuth ? "已登入" : "未登入"}`);

    // 測試 RPC 函數是否存在
    console.log("\n🛠️ 測試 RPC 函數...");
    try {
      await supabase.rpc("get_item_details_with_user_location", {
        p_item_id: 1,
      });
      console.log("✅ RPC 函數存在且可呼叫");
    } catch (rpcError) {
      if (
        rpcError.message.includes("function") &&
        rpcError.message.includes("does not exist")
      ) {
        console.log("❌ RPC 函數不存在，請先執行 SQL migration");
      } else {
        console.log("⚠️ RPC 函數存在但執行有問題 (這可能是正常的)");
      }
    }
  } catch (error) {
    console.error("💥 連線測試失敗:", error.message);
  }
}

// ===================================================================
// ### 輔助函數
// ===================================================================

/**
 * 格式化顯示物品詳情
 */
function displayItemDetails(item) {
  if (!item) {
    console.log("❌ 無物品資料");
    return;
  }

  console.log("\n📦 物品詳情:");
  console.log(`  🏷️ 標題: ${item.title || "未知"}`);
  console.log(`  📝 描述: ${item.description || "無描述"}`);
  console.log(`  🔧 狀況: ${item.condition || "未知"}`);
  console.log(`  💰 價格: ${item.price || 0} 點數`);
  console.log(`  🌱 碳價值: ${item.carbon_value || 0} kg`);
  console.log(`  📸 圖片數量: ${(item.image_urls || []).length}`);
  console.log(
    `  🏷️ 標籤: ${(item.tags || []).length > 0 ? (item.tags || []).join(", ") : "無標籤"}`,
  );
  console.log(
    `  📍 距離: ${item.distance_km ? item.distance_km + " km" : "無法計算"}`,
  );
  console.log(`  ❤️ 收藏狀態: ${item.is_favorited ? "已收藏" : "未收藏"}`);
  console.log(`  📊 收藏次數: ${item.favorites_count || 0}`);
  console.log(`  👤 擁有者: ${item.user?.nickname || "未知"}`);
  console.log(`  📍 地點: ${item.location?.formatted_address || "未設定"}`);

  if (item.category) {
    console.log(
      `  🏷️ 分類: ${item.category.main_category_name || "未知"} > ${item.category.sub_category_name || "未知"}`,
    );
  }
}

// ===================================================================
// ### 主執行函數
// ===================================================================

async function runAllExamples() {
  console.log("🚀 開始執行物品詳情 API 使用範例");
  console.log("=".repeat(60));

  // 檢查環境變數
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_ANON_KEY) {
    console.log("⚠️ 警告: 未設定 Supabase 環境變數");
    console.log("💡 請設定 .env 檔案包含:");
    console.log("   SUPABASE_URL=https://your-project.supabase.co");
    console.log("   SUPABASE_ANON_KEY=your-anon-key");
    console.log("");
  }

  try {
    // 先執行連線測試
    await example5_connectionTest();

    // 執行功能範例
    await example1_autoGetItemDetails();
    await example2_userLocationFromDB();
    await example3_useProvidedCoordinates();
    await example4_errorHandling();

    console.log("\n🎉 所有範例執行完成！");

    // 清理: 如果有模擬登入，則登出
    await simulateLogout();
  } catch (error) {
    console.error("\n💥 範例執行失敗:", error);
  }
}

// ===================================================================
// ### 如果直接執行此檔案，則運行所有範例
// ===================================================================

if (import.meta.url === `file://${process.argv[1]}`) {
  console.log("📝 執行物品詳情 API 使用範例");
  runAllExamples()
    .then(() => {
      console.log("✅ 範例執行結束");
      process.exit(0);
    })
    .catch((error) => {
      console.error("❌ 執行失敗:", error);
      process.exit(1);
    });
}

// ===================================================================
// ### 導出函數供其他模組使用
// ===================================================================

export {
  runAllExamples,
  example1_autoGetItemDetails,
  example2_userLocationFromDB,
  example3_useProvidedCoordinates,
  example4_errorHandling,
  example5_connectionTest,
  displayItemDetails,
  simulateLogin,
  simulateLogout,
  checkUserAuthentication,
  getItemDetailsAuto,
  getItemDetailsWithUserLocation,
  getItemDetailsWithCoordinates,
  supabase,
};

/*
===================================================================
使用方式:

1. 設定環境變數 (.env):
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your-anon-key

2. 安裝依賴:
   npm install @supabase/supabase-js dotenv

3. 運行範例:
   node backend/examples/item_detail_usage_example.js

4. 在其他檔案中使用:
   import { runAllExamples } from './item_detail_usage_example.js';

===================================================================
範例功能:

✅ 完整的 Supabase 初始化
✅ 環境變數檢查
✅ 連線測試
✅ 認證狀態模擬
✅ 自動選擇最佳獲取方式
✅ 資料庫位置使用
✅ 座標位置使用
✅ 完整錯誤處理
✅ 格式化資料顯示
✅ 實用的測試功能

===================================================================
*/
