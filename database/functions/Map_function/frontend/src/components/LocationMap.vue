<template>
  <div class="location-map-container">
    <button
      @click="handleGetLocation"
      :disabled="locationState.loading"
      class="location-button"
    >
      {{ locationState.loading ? '正在定位中...' : '取得我的位置並顯示在地圖上' }}
    </button>

    <p v-if="locationState.error" class="error-message">
      {{ locationState.error }}
    </p>

    <!-- 地圖始終顯示，使用當前位置或預設位置 -->
    <div class="map-container">
      <GMapMap
        ref="mapRef"
        :center="mapCenter"
        :zoom="mapZoom"
        :options="mapOptions"
      >
        <GMapMarker v-if="locationState.coords" :position="locationState.coords" />
      </GMapMap>
    </div>

    <p v-if="locationState.success" class="success-message">
      位置已成功儲存到資料庫！
    </p>
  </div>
</template>

<script setup>
import { reactive, ref, computed, onMounted } from 'vue';
import { supabase } from '../supabase';

// --- 1. 狀態管理 ---
const mapRef = ref(null);
const isMapLoaded = ref(true); // vue-google-maps 會自動處理載入
const locationState = reactive({
  loading: false,
  error: null,
  coords: null,
  success: false,
});

// 預設地圖中心（台灣中心位置）
const defaultCenter = { lat: 23.9739, lng: 120.9820 };

// 地圖選項
const mapOptions = {
  zoomControl: true,
  mapTypeControl: false,
  scaleControl: true,
  streetViewControl: false,
  rotateControl: false,
  fullscreenControl: true,
  disableDefaultUI: false
};

// 地圖中心：如果有使用者位置就用使用者位置，否則用預設位置
const mapCenter = computed(() => {
  return locationState.coords || defaultCenter;
});

// 地圖縮放等級：有使用者位置時放大，否則顯示整個台灣
const mapZoom = computed(() => {
  return locationState.coords ? 16 : 8;
});

// --- 2. 核心邏輯 ---

/**
 * 將 Geolocation API Promise 化，以便使用 async/await
 */
const getCurrentLocation = () => {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      return reject(new Error('您的瀏覽器不支援地理定位功能。'));
    }
    navigator.geolocation.getCurrentPosition(
      (position) => resolve(position.coords),
      (error) => {
        let errorMessage = '定位失敗，請確認已授權瀏覽器讀取位置。';
        if (error.code === 1) { // PERMISSION_DENIED
          errorMessage = '您已拒絕位置授權，請至瀏覽器設定中重新開啟。';
        }
        return reject(new Error(errorMessage));
      },
      {
        enableHighAccuracy: true, // 啟用高精確度
        timeout: 10000, // 10秒超時
        maximumAge: 0 // 不使用快取位置
      }
    );
  });
};

/**
 * 使用 Google Geocoding API 將經緯度轉換為地址
 */
const getFormattedAddress = async (lat, lng) => {
  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY;
  if (!apiKey) {
    console.warn('缺少 Google Maps API Key，無法進行地理編碼');
    return null;
  }

  try {
    const response = await fetch(
      `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${apiKey}&language=zh-TW`
    );
    const data = await response.json();

    if (data.status === 'OK' && data.results.length > 0) {
      // 返回第一個結果的格式化地址
      return data.results[0].formatted_address;
    } else {
      console.warn('地理編碼失敗:', data.status);
      return null;
    }
  } catch (error) {
    console.error('地理編碼錯誤:', error);
    return null;
  }
};

/**
 * 安全地呼叫 Supabase Edge Function
 * 注意：這裡使用現有的 locations 表結構，包含更多欄位
 */
const saveLocationToSupabase = async (coords) => {
  try {
    const { data: { session }, error: sessionError } = await supabase.auth.getSession();
    if (sessionError) throw sessionError;
    if (!session) {
      locationState.error = "請先登入！";
      return;
    }

    // 進行地理編碼，獲取格式化地址
    const formattedAddress = await getFormattedAddress(coords.lat, coords.lng);

    // 呼叫 Edge Function
    const { data, error } = await supabase.functions.invoke('save-location', {
      body: {
        latitude: coords.lat,
        longitude: coords.lng,
        formatted_address: formattedAddress
      },
    });

    if (error) throw error;

    console.log('位置已成功儲存！', data);
    locationState.success = true;

    // 3秒後清除成功訊息
    setTimeout(() => {
      locationState.success = false;
    }, 3000);

  } catch (error) {
    console.error('儲存位置失敗:', error);
    locationState.error = '無法儲存您的位置，請稍後再試。';
  }
};

// --- 3. 事件處理 ---

/**
 * 處理點擊事件，觸發定位
 */
const handleGetLocation = async () => {
  locationState.loading = true;
  locationState.error = null;
  locationState.coords = null;
  locationState.success = false;

  try {
    const coords = await getCurrentLocation();
    locationState.coords = { lat: coords.latitude, lng: coords.longitude };

    // 成功取得座標後，送到後端儲存
    await saveLocationToSupabase(locationState.coords);

  } catch (error) {
    locationState.error = error.message;
  } finally {
    locationState.loading = false;
  }
};
</script>

<style scoped>
.location-map-container {
  width: 100%;
  height: 100%;
  position: relative;
  overflow: hidden;
}

/* 地圖容器 - 填滿整個空間 */
.map-container {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  width: 100%;
  height: 100%;
}

/* 只強制最外層的 vue-map 容器填滿，不影響內部互動元素 */
.map-container :deep(.vue-map-container) {
  width: 100% !important;
  height: 100% !important;
}

.map-container :deep(.vue-map) {
  width: 100% !important;
  height: 100% !important;
}

/* 按鈕浮動在地圖上方 */
.location-button {
  position: absolute;
  top: 20px;
  left: 20px;
  z-index: 1000;
  background-color: #4CAF50;
  color: white;
  padding: 12px 24px;
  font-size: 16px;
  font-weight: 500;
  border: none;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.3s;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
}

.location-button:hover:not(:disabled) {
  background-color: #45a049;
  transform: translateY(-2px);
  box-shadow: 0 6px 16px rgba(0, 0, 0, 0.25);
}

.location-button:disabled {
  background-color: #cccccc;
  cursor: not-allowed;
  transform: none;
}

/* 錯誤訊息浮動在地圖上方 */
.error-message {
  position: absolute;
  top: 90px;
  left: 20px;
  right: 20px;
  z-index: 1000;
  color: #f44336;
  padding: 12px 16px;
  background-color: #ffebee;
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
  max-width: 400px;
  font-weight: 500;
}

/* 成功訊息浮動在地圖上方 */
.success-message {
  position: absolute;
  top: 90px;
  left: 20px;
  right: 20px;
  z-index: 1000;
  color: #4CAF50;
  padding: 12px 16px;
  background-color: #e8f5e9;
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
  max-width: 400px;
  font-weight: 500;
}
</style>
