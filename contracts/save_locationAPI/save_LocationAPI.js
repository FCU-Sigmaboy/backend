/**
 * 使用瀏覽器 Geolocation API 取得用戶當前位置
 *
 * @param {Object} [options] - Geolocation API 選項
 * @param {boolean} [options.enableHighAccuracy=true] - 是否要求高精度定位
 * @param {number} [options.timeout=10000] - 超時時間（毫秒）
 * @param {number} [options.maximumAge=0] - 快取位置的最長時間（毫秒）
 *
 * @returns {Promise<Object>} 位置資訊
 * @returns {number} returns.latitude - 緯度
 * @returns {number} returns.longitude - 經度
 * @returns {number} returns.accuracy - 精度（公尺）
 *
 * @throws {Error} 瀏覽器不支援地理定位
 * @throws {Error} 用戶拒絕提供位置權限
 * @throws {Error} 無法取得位置資訊
 * @throws {Error} 取得位置逾時
 *
 * @example
 * // 取得用戶當前位置
 * getCurrentPosition()
 *   .then(pos => console.log('當前位置:', pos.latitude, pos.longitude))
 *   .catch(err => console.error('定位失敗:', err.message));
 *
 * @example
 * // 自訂選項
 * getCurrentPosition({ timeout: 5000, enableHighAccuracy: false })
 *   .then(pos => console.log('位置:', pos));
 */
function getCurrentPosition(options = {}) {
  return new Promise((resolve, reject) => {
    // 檢查瀏覽器是否支援 Geolocation API
    if (!navigator.geolocation) {
      reject(new Error('瀏覽器不支援地理定位功能'));
      return;
    }

    const defaultOptions = {
      enableHighAccuracy: true,  // 使用 GPS 等高精度定位
      timeout: 10000,            // 10 秒超時
      maximumAge: 0              // 不使用快取位置
    };

    const geolocationOptions = { ...defaultOptions, ...options };

    navigator.geolocation.getCurrentPosition(
      // 成功回調
      (position) => {
        resolve({
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          accuracy: position.coords.accuracy
        });
      },
      // 錯誤回調
      (error) => {
        switch (error.code) {
          case error.PERMISSION_DENIED:
            reject(new Error('用戶拒絕提供位置權限'));
            break;
          case error.POSITION_UNAVAILABLE:
            reject(new Error('無法取得位置資訊'));
            break;
          case error.TIMEOUT:
            reject(new Error('取得位置逾時，請稍後再試'));
            break;
          default:
            reject(new Error('取得位置時發生未知錯誤'));
        }
      },
      geolocationOptions
    );
  });
}

/**
 * save-location edge function API contract
 * 依據 LOCATION_API_FRONTEND_GUIDE.md v2.0
 *
 * @param {Object} params - 地點資訊
 * @param {number} params.latitude - 緯度（必須為有效的數字）
 * @param {number} params.longitude - 經度（必須為有效的數字）
 * @param {'家'|'公司'} params.type - 地點類型（僅支援「家」和「公司」）
 * @param {boolean} [params.is_primary] - 是否設為主要地點（可選，省略時由後端自動判斷）
 * @param {string} userToken - JWT Token（必須為有效的授權 token）
 *
 * @returns {Promise<Object>} API 回應
 * @returns {boolean} returns.success - 請求是否成功
 * @returns {Object} returns.data - 地點資料
 * @returns {number} returns.data.id - 地點 ID
 * @returns {number} returns.data.latitude - 緯度
 * @returns {number} returns.data.longitude - 經度
 * @returns {string} returns.data.district - 行政區（如：台中市南屯區）
 * @returns {string} returns.data.type - 地點類型
 * @returns {boolean} returns.data.is_primary - 是否為主要地點
 *
 * @throws {Error} 緯度與經度必須為數字
 * @throws {Error} 地點類型僅支援「家」和「公司」
 * @throws {Error} 缺少使用者授權 Token
 * @throws {Error} 首次建立地點必須為「家」（400）
 * @throws {Error} 您已經有「X」類型的地點（400）
 * @throws {Error} 已達地點數量上限（400）
 * @throws {Error} 未授權，請重新登入（401）
 * @throws {Error} 伺服器錯誤，請稍後再試（500）
 * @throws {Error} 網路連線失敗
 *
 * @example
 * // 首次建立地點（必須為「家」）
 * saveLocation({ latitude: 24.1817, longitude: 120.7344, type: '家' }, userToken)
 *   .then(res => console.log('成功:', res.data))
 *   .catch(err => console.error('失敗:', err.message));
 *
 * @example
 * // 建立第二個地點（公司）並設為主要
 * saveLocation({
 *   latitude: 24.2,
 *   longitude: 120.8,
 *   type: '公司',
 *   is_primary: true
 * }, userToken);
 */
async function saveLocation({ latitude, longitude, type, is_primary }, userToken) {
  // 參數基本驗證
  if (typeof latitude !== 'number' || typeof longitude !== 'number') {
    throw new Error('緯度與經度必須為數字');
  }
  if (type !== '家' && type !== '公司') {
    throw new Error('地點類型僅支援「家」和「公司」');
  }
  if (!userToken || typeof userToken !== 'string') {
    throw new Error('缺少使用者授權 Token');
  }

  const body = { latitude, longitude, type };
  if (typeof is_primary === 'boolean') body.is_primary = is_primary;

  try {
    const response = await fetch('https://your-project.supabase.co/functions/v1/save-location', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${userToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body)
    });

    const data = await response.json();

    if (!response.ok) {
      switch (response.status) {
        case 400:
          // 可能的錯誤：
          // - "首次建立地點必須為「家」"
          // - "您已經有「家」類型的地點"
          // - "已達地點數量上限"
          // - "無效的地點類型（僅支援「家」和「公司」）"
          // - "無效的座標格式"
          throw new Error(data.error || '請求錯誤');
        case 401:
          // 未授權：token 無效或過期
          throw new Error(data.error || '未授權，請重新登入');
        case 500:
          // 伺服器內部錯誤（如地址解析失敗、資料庫錯誤）
          throw new Error(data.error || '伺服器錯誤，請稍後再試');
        default:
          throw new Error(data.error || '未知錯誤');
      }
    }

    return data;
  } catch (error) {
    // 處理網路錯誤或其他非 HTTP 錯誤
    if (error.message && (
      error.message.includes('請求錯誤') ||
      error.message.includes('未授權') ||
      error.message.includes('伺服器錯誤') ||
      error.message.includes('緯度') ||
      error.message.includes('地點類型') ||
      error.message.includes('授權 Token')
    )) {
      // 重新拋出業務邏輯錯誤
      throw error;
    }
    // 網路連線錯誤
    throw new Error('網路連線失敗，請檢查您的網路');
  }
}

/**
 * 使用範例：
 *
 * // 範例 1: 首次建立地點（必須為「家」）
 * saveLocation({ latitude: 24.1817, longitude: 120.7344, type: '家' }, userToken)
 *   .then(res => {
 *     console.log('成功:', res.data);
 *     // res.data: { id: 123, latitude: 24.1817, longitude: 120.7344,
 *     //            district: "台中市南屯區", type: "家", is_primary: true }
 *   })
 *   .catch(err => {
 *     console.error('失敗:', err.message);
 *     alert(err.message);
 *   });
 *
 * // 範例 2: 建立第二個地點（公司）並設為主要
 * saveLocation({
 *   latitude: 24.2,
 *   longitude: 120.8,
 *   type: '公司',
 *   is_primary: true  // 會將「家」改為非主要
 * }, userToken)
 *   .then(res => console.log('公司地點已設為主要:', res.data))
 *   .catch(err => console.error('錯誤:', err.message));
 *
 * // 範例 3: 完整的錯誤處理
 * try {
 *   const result = await saveLocation({
 *     latitude: 24.1817,
 *     longitude: 120.7344,
 *     type: '家'
 *   }, userToken);
 *
 *   if (result.success) {
 *     console.log('地點已儲存:', result.data);
 *   }
 * } catch (error) {
 *   // 根據錯誤訊息進行不同處理
 *   if (error.message.includes('未授權')) {
 *     // 導向登入頁
 *     window.location.href = '/login';
 *   } else if (error.message.includes('網路連線')) {
 *     alert('請檢查您的網路連線');
 *   } else {
 *     alert(error.message);
 *   }
 * }
 *
 * // 範例 4: 使用瀏覽器取得當前位置並儲存
 * async function saveCurrentLocationAsHome(userToken) {
 *   try {
 *     // 先取得用戶當前位置
 *     console.log('正在取得您的位置...');
 *     const position = await getCurrentPosition();
 *     console.log('位置取得成功:', position);
 *
 *     // 儲存為「家」
 *     const result = await saveLocation({
 *       latitude: position.latitude,
 *       longitude: position.longitude,
 *       type: '家'
 *     }, userToken);
 *
 *     console.log('地點已儲存:', result.data);
 *     alert('已成功將您的當前位置設為「家」');
 *     return result;
 *   } catch (error) {
 *     if (error.message.includes('拒絕')) {
 *       alert('需要位置權限才能使用此功能，請在瀏覽器設定中允許位置存取');
 *     } else if (error.message.includes('不支援')) {
 *       alert('您的瀏覽器不支援地理定位功能');
 *     } else {
 *       alert('儲存失敗: ' + error.message);
 *     }
 *     throw error;
 *   }
 * }
 *
 * // 範例 5: 在 React 元件中使用
 * function LocationSetup() {
 *   const [loading, setLoading] = useState(false);
 *
 *   const handleUseCurrentLocation = async () => {
 *     setLoading(true);
 *     try {
 *       const position = await getCurrentPosition();
 *       const result = await saveLocation({
 *         latitude: position.latitude,
 *         longitude: position.longitude,
 *         type: '家'
 *       }, userToken);
 *
 *       toast.success('地點已儲存');
 *       navigate('/locations');
 *     } catch (error) {
 *       toast.error(error.message);
 *     } finally {
 *       setLoading(false);
 *     }
 *   };
 *
 *   return (
 *     <button onClick={handleUseCurrentLocation} disabled={loading}>
 *       {loading ? '定位中...' : '使用當前位置'}
 *     </button>
 *   );
 * }
 */

module.exports = { getCurrentPosition, saveLocation };
